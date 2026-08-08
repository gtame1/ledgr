defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateAnalyticsFctConsultation do
  use Ecto.Migration

  @moduledoc """
  First view of the `analytics` semantic layer — see
  `docs/design/reporting-architecture.md` (layer 1) and
  `docs/design/hd-metric-census.md` for the measurements that motivated it.

  The problem it solves: "paid consultation" currently has four different
  definitions across the HD modules. Measured 2026-08-01 over consultations
  completed since May, the Dashboard reported 66 and Unit Economics 123 — the
  gap being 55 free/comped consults and 2 refunds counted as revenue.

  This view applies each business rule **once** and exposes the result as a
  plain column, so no consumer re-derives one. The rules are ported from the
  existing Elixir — `TestAccounts`, `ConsultationAccounting`, `MonthlyReport` —
  not reinvented.

  Ownership: `consultations`, `conversations`, `doctors`, `patients` and
  `corporate_accounts` are bot-owned base tables in `public`. Everything in
  `analytics` is Ledgr-owned, so this needs no coordination with the bot's
  migration tooling.

  A plain view, not materialized: always fresh, no refresh job, no staleness
  bugs. Revisit only if it measurably hurts.
  """

  def up do
    execute("CREATE SCHEMA IF NOT EXISTS analytics")

    # The view reads five bot-owned base tables that only exist on the Neon HD
    # database. On a local ledgr-only Postgres the CREATE VIEW raises
    # `undefined_table`, which fails `mix ecto.migrate` for HelloDoctor — and
    # because Phoenix.Ecto.CheckRepoStatus checks every configured repo, that
    # 503s the entire app for every domain, not just HD. Skip instead, the same
    # way the AMP lead_crm backfill does.
    if bot_tables_present?() do
      create_view()
    else
      IO.puts(
        :stderr,
        "[migration] consultations/conversations/doctors/patients/corporate_accounts " <>
          "(bot-owned) not present — skipping analytics.fct_consultation " <>
          "(fresh ledgr-only DB). Set HELLO_DOCTOR_DATABASE_URL to build it."
      )
    end
  end

  defp bot_tables_present? do
    %{rows: [[present]]} =
      repo().query!("""
      SELECT to_regclass('public.consultations')      IS NOT NULL
         AND to_regclass('public.conversations')      IS NOT NULL
         AND to_regclass('public.doctors')            IS NOT NULL
         AND to_regclass('public.patients')           IS NOT NULL
         AND to_regclass('public.corporate_accounts') IS NOT NULL
      """)

    present
  end

  defp create_view do
    execute("""
    CREATE OR REPLACE VIEW analytics.fct_consultation AS
    SELECT
      c.id,
      c.conversation_id,
      c.patient_id,
      c.doctor_id,
      c.corporate_account_id,

      -- Descriptive passthrough
      c.status,
      c.consultation_type,
      c.payment_status,
      COALESCE(c.payment_source, 'stripe')            AS payment_source,
      conv.tenant,

      -- Raw timestamps (UTC, as stored)
      c.assigned_at,
      c.accepted_at,
      c.completed_at,
      c.payment_confirmed_at,

      -- Mexico-local dates. The base columns are naive timestamps holding UTC;
      -- comparing them to an MX-local date is the recurring undercount bug.
      (c.assigned_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date
                                                      AS assigned_at_mx,
      (c.completed_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date
                                                      AS completed_at_mx,
      (c.payment_confirmed_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date
                                                      AS paid_at_mx,

      -- Money state. is_paid / is_comped / is_refunded are mutually exclusive
      -- and together equal is_collected.
      (c.payment_status IN ('paid','confirmed','refunded'))        AS is_collected,
      (c.payment_status IN ('paid','confirmed')
        AND c.payment_amount > 0)                                  AS is_paid,
      (c.payment_status IN ('paid','confirmed')
        AND COALESCE(c.payment_amount, 0) = 0)                     AS is_comped,
      (c.payment_status = 'refunded')                              AS is_refunded,

      -- Classification
      (c.targeted_doctor_id IS NOT NULL)                           AS is_direct,
      (COALESCE(c.payment_source, 'stripe') = 'corporate')         AS is_corporate,
      (
        COALESCE(c.payment_source, '') = 'test'
        OR EXISTS (
          SELECT 1 FROM patients tp
          WHERE tp.id = c.patient_id
            AND (tp.phone IN ('5215512950400','5215543408539','5215536713304')
                 OR tp.id IN ('2ed77952-cead-4bc4-bc44-51f5b5052d76'))
        )
      )                                                            AS is_test,

      -- Revenue recognised for this consultation, MXN.
      --
      -- The corporate branch mirrors ConsultationAccounting's
      -- corporate_revenue_cents/1 exactly: fall back to the employer's
      -- contracted rate when no amount was recorded. Note the fallback fires
      -- on zero as well as NULL — a corporate consult booked at 0 still
      -- credits 4000 the full rate, so a COALESCE-on-NULL-only test would
      -- report 0 here while the GL says otherwise, breaking reconciliation.
      (CASE
         WHEN c.payment_status = 'refunded' THEN 0::float8
         WHEN COALESCE(c.payment_source, 'stripe') = 'corporate'
           THEN (CASE
                   WHEN COALESCE(c.payment_amount, 0) > 0 THEN c.payment_amount
                   ELSE COALESCE(ca.consultation_rate_mxn::float8, 0)
                 END)
         ELSE COALESCE(c.payment_amount, 0)
       END)                                                        AS gross_mxn,

      -- The doctor's rate for this consultation. Mirrors the GL rule in
      -- ConsultationAccounting.doctor_share_sql/2 so figures tie to account
      -- 2000. Keyed on conversations.tenant, NOT is_direct — see the comment
      -- on is_direct.
      (CASE
         WHEN conv.tenant = 'direct' AND COALESCE(d.consultation_fee_mxn, 0) > 0
           THEN d.consultation_fee_mxn::float8
         ELSE 100.0
       END)                                                        AS doctor_share_rate_mxn,

      -- Rate actually accrued to the doctor.
      (CASE
         WHEN c.payment_status IN ('paid','confirmed')
           THEN (CASE
                   WHEN conv.tenant = 'direct' AND COALESCE(d.consultation_fee_mxn, 0) > 0
                     THEN d.consultation_fee_mxn::float8
                   ELSE 100.0
                 END)
         ELSE 0::float8
       END)                                                        AS doctor_share_mxn,

      -- What HD keeps. Negative on comped consults by design: HD pays the
      -- doctor for a consultation the patient did not pay for.
      ((CASE
          WHEN c.payment_status = 'refunded' THEN 0::float8
          WHEN COALESCE(c.payment_source, 'stripe') = 'corporate'
            THEN (CASE
                    WHEN COALESCE(c.payment_amount, 0) > 0 THEN c.payment_amount
                    ELSE COALESCE(ca.consultation_rate_mxn::float8, 0)
                  END)
          ELSE COALESCE(c.payment_amount, 0)
        END)
       -
       (CASE
          WHEN c.payment_status IN ('paid','confirmed')
            THEN (CASE
                    WHEN conv.tenant = 'direct' AND COALESCE(d.consultation_fee_mxn, 0) > 0
                      THEN d.consultation_fee_mxn::float8
                    ELSE 100.0
                  END)
          ELSE 0::float8
        END))                                                      AS hd_commission_mxn

    FROM consultations c
    LEFT JOIN conversations   conv ON conv.id = c.conversation_id
    LEFT JOIN doctors         d    ON d.id    = c.doctor_id
    LEFT JOIN corporate_accounts ca ON ca.id  = c.corporate_account_id
    """)

    # Documentation is not optional here: these comments are what let a query
    # author (human or agent) get the rules right without reading the Elixir.
    execute("""
    COMMENT ON VIEW analytics.fct_consultation IS
    'One row per consultation, with HD business rules pre-applied. Start every
     consultation question here rather than from public.consultations. Rules
     ported from TestAccounts, ConsultationAccounting and MonthlyReport.
     Payout ELIGIBILITY is not modelled — explicit pay/skip decisions and
     overrides still live in MonthlyReport.'
    """)

    comment!(
      "is_collected",
      "payment_status IN (paid, confirmed, refunded). Equals is_paid OR is_comped OR is_refunded."
    )

    comment!(
      "is_paid",
      "Real money received: paid/confirmed AND payment_amount > 0. This is the strict revenue definition; use it for paid-consult counts."
    )

    comment!(
      "is_comped",
      "Free consultation: paid/confirmed but zero or NULL amount (experiment or courtesy). Counted as paid by two pages before 2026-08 — that was the bug this layer fixes."
    )

    comment!("is_refunded", "payment_status = refunded. gross_mxn is 0 for these; money was returned.")

    comment!(
      "is_direct",
      "A doctor brought their own patient: targeted_doctor_id IS NOT NULL. This is the attribution truth. Note doctor_share_* keys on conversations.tenant instead, to match what the GL posted; the two agree on every peso as of 2026-08-01 and check_direct_attribution_agrees guards the difference."
    )

    comment!("is_corporate", "Employer-paid consultation (payment_source = corporate).")

    comment!(
      "is_test",
      "Internal test traffic: /prueba bypass (payment_source = test) or a known QA phone/patient id. Keep in sync with Ledgr.Domains.HelloDoctor.TestAccounts — the lists are duplicated here deliberately so the view is self-contained, and must be reconciled when either changes."
    )

    comment!(
      "gross_mxn",
      "Revenue recognised, MXN. 0 when refunded. Corporate consults fall back to the employer's contracted consultation_rate_mxn when payment_amount is zero or NULL, mirroring ConsultationAccounting.corporate_revenue_cents/1 so the column ties to account 4000. This does NOT apply revenue-posting eligibility (cancelled/failed consults are excluded upstream by MonthlyPayoutRun) — a reconciliation check must account for that."
    )

    comment!(
      "doctor_share_rate_mxn",
      "The doctor's per-consultation rate, whether or not it was earned. Do NOT sum this — it includes pending and cancelled consultations. Sum doctor_share_mxn instead."
    )

    comment!(
      "doctor_share_mxn",
      "Rate actually accrued to the doctor (0 unless paid/confirmed). Safe to sum. Comped consults DO accrue — HD pays the doctor for free consultations."
    )

    comment!(
      "hd_commission_mxn",
      "gross_mxn - doctor_share_mxn. Legitimately negative on comped consults; a negative total is the free-consult subsidy, not a bug."
    )

    comment!(
      "completed_at_mx",
      "Mexico-local calendar date of completion. Use this for any date filter or grouping — the raw completed_at is naive UTC and comparing it to an MX date undercounts."
    )

    comment!("assigned_at_mx", "Mexico-local calendar date of doctor assignment. See completed_at_mx.")
    comment!("paid_at_mx", "Mexico-local calendar date of payment confirmation. See completed_at_mx.")
  end

  def down do
    execute("DROP VIEW IF EXISTS analytics.fct_consultation")
    # The schema is left in place — other analytics objects may live in it.
  end

  defp comment!(column, text) do
    execute("COMMENT ON COLUMN analytics.fct_consultation.#{column} IS '#{escape(text)}'")
  end

  defp escape(text), do: String.replace(text, "'", "''")
end
