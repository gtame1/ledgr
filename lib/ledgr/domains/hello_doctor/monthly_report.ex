defmodule Ledgr.Domains.HelloDoctor.MonthlyReport do
  @moduledoc """
  Monthly doctor-payout report — one row per consultation in the
  selected month, showing what's still owed to each doctor net of
  payouts already made and retentions due / applied.

  Per consultation:

      doctor_share              = 100 MXN when pay_to_doc; 0 otherwise
      iva_retention_to_apply    = 0 (no IVA retention on honorarios)
      isr_retention_to_apply    = 2.5 if doctor.has_correct_rfc, else 20

      paid_out_amount           = doctor_payouts.amount_cents / 100
      iva_retentions_applied    = doctor_payouts.iva_retention_cents / 100
      isr_retentions_applied    = doctor_payouts.isr_retention_cents / 100

      owed_to_doctor       = doctor_share - paid_out_amount
      net_payment_pending  = owed_to_doctor
                           - (iva_retention_to_apply - iva_retentions_applied)
                           - (isr_retention_to_apply - isr_retentions_applied)

  Rows with `net_payment_pending == 0` are filtered out by default.
  Pass `include_settled: true` (`?include_settled=true`) to keep them.

  The query excludes refunded consultations *unless* they have an
  explicit `pay_doctor=true` override in `consultation_payout_decisions`.
  Test patient + test doctor are hardcoded out.

  Period defaults to the previous calendar month in Mexico City time.
  """

  alias Ledgr.Repo
  alias Elixlsx.{Workbook, Sheet}

  @doctor_share_mxn 100.0

  # Mexican payroll retention rates expressed as percentage points so
  # they line up with the report column ("2.5" / "20").
  @iva_rate_pct 0.0
  @isr_rate_with_rfc_pct 2.5
  @isr_rate_without_rfc_pct 20.0

  # Hard-coded exclusions — both are bot-managed so we can't tag them
  # in-schema; gating here is the simplest approach.
  @test_patient_id "2ed77952-cead-4bc4-bc44-51f5b5052d76"
  @test_doctor_id "03f3b382-3ae3-4c0c-8d8e-2382b241b1d8"

  # "Collected / payable" — the single source of truth for whether a
  # consultation owes the doctor, shared by `auto_eligible` and `pay_to_doc`
  # so they can't drift. A consultation is collected when ANY of:
  #   • a non-refunded Stripe payment synced with status 'paid';
  #   • corporate (employer-billed, no Stripe row but doctor IS owed);
  #   • a bot-sanctioned 100%-discount / free consult (`cs_no_payment_*`
  #     intent, confirmed — $0 charged, doctor still did the work);
  #   • collected on the bot side (confirmed/paid with a real charge) but the
  #     `stripe_payments` row hasn't synced yet — still owed. This last clause
  #     mirrors the /doctor-payouts page's `payment_amount` fallback so the two
  #     reports agree; without it, a confirmed consult with no synced Stripe row
  #     (e.g. direct patients) silently collapses to $0 owed and drops out.
  # COALESCE(... = 'paid', FALSE) keeps this a true boolean: a consult with no
  # Stripe row reads FALSE, not NULL (NULL slips past CASE/NOT and posts phantom
  # $0 / negative rows). References `so` (stripe_one) and `c` (consultations).
  @collected_sql """
  COALESCE(so.status = 'paid', FALSE)
  OR COALESCE(c.payment_source, 'stripe') = 'corporate'
  OR (c.stripe_payment_intent_id LIKE 'cs_no_payment_%'
      AND COALESCE(c.payment_status, '') IN ('paid', 'confirmed'))
  OR (so.cid IS NULL
      AND COALESCE(c.payment_status, '') IN ('paid', 'confirmed')
      AND COALESCE(c.payment_amount, 0) > 0
      AND c.stripe_payment_intent_id IS NOT NULL
      AND c.stripe_payment_intent_id NOT LIKE 'pi_test_bypass_%')
  """

  # ── Period helpers ─────────────────────────────────────────────

  @doc "Returns {first_day, last_day} of the previous calendar month."
  def last_month_range do
    today = Ledgr.Domains.HelloDoctor.today()
    last_month_range(today)
  end

  def last_month_range(today) do
    today
    |> Date.beginning_of_month()
    |> Date.add(-1)
    |> month_range()
  end

  @doc "Returns {first_day, last_day} of the month containing `date`."
  def month_range(date) do
    first = Date.beginning_of_month(date)
    last = Date.end_of_month(first)
    {first, last}
  end

  @doc "Returns the {start, end} of the month for a YYYY-MM string, or nil on bad input."
  def parse_month(nil), do: nil
  def parse_month(""), do: nil

  def parse_month(<<year::binary-size(4), "-", month::binary-size(2)>>) do
    with {y, ""} <- Integer.parse(year),
         {m, ""} <- Integer.parse(month),
         {:ok, date} <- Date.new(y, m, 1) do
      month_range(date)
    else
      _ -> nil
    end
  end

  def parse_month(_), do: nil

  @doc "Adds `n` months to the first day of `date`'s month."
  def shift_month(date, n) when is_integer(n) do
    Date.beginning_of_month(date) |> shift_month_by(n)
  end

  defp shift_month_by(date, 0), do: date

  defp shift_month_by(date, n) when n > 0 do
    date |> Date.end_of_month() |> Date.add(1) |> shift_month_by(n - 1)
  end

  defp shift_month_by(date, n) when n < 0 do
    date |> Date.add(-1) |> Date.beginning_of_month() |> shift_month_by(n + 1)
  end

  @doc "Returns a list of {label, YYYY-MM} for the last `n` months (most recent first)."
  def month_options(n \\ 12) do
    today = Ledgr.Domains.HelloDoctor.today()
    first_of_this_month = Date.beginning_of_month(today)

    0..(n - 1)
    |> Enum.map(fn i -> shift_month_by(first_of_this_month, -i) end)
    |> Enum.map(fn d ->
      label = Calendar.strftime(d, "%B %Y")
      key = Calendar.strftime(d, "%Y-%m")
      {label, key}
    end)
  end

  # ── Main API ───────────────────────────────────────────────────

  @doc """
  Generates the monthly report for the given period.

  Options:
    * `:include_settled` — when `true`, keeps rows with
      `net_payment_pending == 0`. Defaults to `false`.
  """
  def generate(start_date, end_date, opts \\ []) do
    include_settled? = Keyword.get(opts, :include_settled, false)

    consultations =
      start_date
      |> list_consultations(end_date)
      |> maybe_filter_settled(include_settled?)

    per_doctor = aggregate_by_doctor(consultations)
    totals = totals(consultations, per_doctor)

    %{
      period: {start_date, end_date},
      include_settled?: include_settled?,
      consultations: consultations,
      per_doctor: per_doctor,
      totals: totals
    }
  end

  defp maybe_filter_settled(rows, true), do: rows

  defp maybe_filter_settled(rows, false),
    do: Enum.reject(rows, &(&1.net_payment_pending == 0.0))

  # ── Per-consultation query ─────────────────────────────────────

  @doc """
  One row per consultation. With a date window, restricts to
  `completed_at` in `[start_date, end_date)`; pass `nil` for either bound
  to leave it open (the default "all outstanding" view passes both nil).

  ## Pay eligibility (the default)

  A consultation pays the doctor by default whenever it was **collected**:
  a non-refunded Stripe payment (status `paid`), `payment_source =
  'corporate'`, or a bot-sanctioned 100%-discount / free consult
  (`cs_no_payment_*` intent, confirmed — $0 charged but the doctor still
  did the work). Status is intentionally NOT checked — a paid consultation
  still owes the doctor even if it's not marked `completed`. Refunded or
  uncollected consultations don't pay by default. An explicit
  `consultation_payout_decisions.pay_doctor` row always wins either way
  ("pay anyway" = true, "skip" = false), so the rule is simply:

      pays  ⇔  has a (non-refunded) payment  OR  pay_doctor = true

      pay_to_doc = COALESCE(cpd.pay_doctor, collected?)

  Doctor share is the per-doctor `consultation_fee_mxn` when set (> 0),
  otherwise the global $100. Already-paid amounts are summed across ALL
  payouts a consultation appears in (a consultation can legitimately span
  more than one payout), and the Stripe row is de-duplicated to one
  (preferring a `paid` row) so neither join multiplies the consultation.
  """
  def list_consultations(start_date, end_date) do
    # Bounds are Mexico City wall-clock; `completed_at` is UTC-stored.
    # Helpers convert MX-midnight to UTC instants; nil = open bound.
    start_naive = start_date && Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive(start_date)
    end_exclusive = end_date && Ledgr.Domains.HelloDoctor.mx_day_end_utc_naive(end_date)

    sql = """
    payout_totals AS (
      -- Total cash allocated across each payout's consultations — used to
      -- apportion the payout-level retentions down to each consultation.
      SELECT doctor_payout_id, SUM(amount_cents) AS total_amount_cents
      FROM doctor_payout_consultations
      GROUP BY doctor_payout_id
    ),
    pay_agg AS (
      -- Per-consultation paid-out + retentions, summed across every payout a
      -- consultation appears in (it can span more than one). Cash uses the
      -- per-consultation allocation frozen on the join row (dpc.amount_cents),
      -- NOT the payout total (dp.amount_cents) — otherwise a payout spanning N
      -- consultations credits each one the ENTIRE payout. Retentions live only
      -- at the payout level, so apportion them to each consultation in
      -- proportion to its share of the payout's cash.
      SELECT dpc.consultation_id            AS cid,
             SUM(dpc.amount_cents)          AS amount_cents,
             SUM(CASE WHEN pt.total_amount_cents > 0
                      THEN ROUND(dp.iva_retention_cents::numeric
                                 * dpc.amount_cents / pt.total_amount_cents)
                      ELSE 0 END)           AS iva_cents,
             SUM(CASE WHEN pt.total_amount_cents > 0
                      THEN ROUND(dp.isr_retention_cents::numeric
                                 * dpc.amount_cents / pt.total_amount_cents)
                      ELSE 0 END)           AS isr_cents,
             MAX(dp.payout_date)            AS payout_date
      FROM doctor_payout_consultations dpc
      JOIN doctor_payouts dp ON dp.id = dpc.doctor_payout_id
      JOIN payout_totals pt ON pt.doctor_payout_id = dpc.doctor_payout_id
      GROUP BY dpc.consultation_id
    ),
    stripe_one AS (
      -- One Stripe row per consultation: prefer a 'paid' row, then latest.
      SELECT DISTINCT ON (s.cid)
             s.cid, s.status, s.amount, s.stripe_fee, s.paid_at, s.discount_code
      FROM (
        SELECT c.id AS cid, p.status, p.amount, p.stripe_fee, p.paid_at, p.discount_code
        FROM consultations c
        JOIN stripe_payments p ON (
          p.consultation_id = c.id
          OR (p.consultation_id IS NULL
              AND c.stripe_payment_intent_id IS NOT NULL
              AND p.stripe_payment_intent_id = c.stripe_payment_intent_id)
        )
      ) s
      ORDER BY s.cid, (s.status = 'paid') DESC, s.paid_at DESC NULLS LAST
    ),
    base AS (
      SELECT
        c.id                                       AS consultation_id,
        c.completed_at,
        c.assigned_at,
        c.duration_minutes,
        c.consultation_type,
        c.status                                   AS consultation_status,
        so.status                                  AS payment_status,
        c.payment_amount,
        c.patient_rating,
        d.id                                       AS doctor_id,
        d.name                                     AS doctor_name,
        d.specialty                                AS doctor_specialty,
        COALESCE(d.has_correct_rfc, FALSE)         AS has_correct_rfc,
        pt.id                                      AS patient_id,
        COALESCE(pt.full_name, pt.display_name)    AS patient_name,
        -- Amount charged to the patient. Prefer the synced Stripe row; fall
        -- back to the consultation's own `payment_amount` when no Stripe row
        -- has landed yet (e.g. direct consults, which don't produce a
        -- stripe_payments row). Without the fallback the charged amount and
        -- HD commission read blank while the doctor is still owed — the row
        -- looks like "$0 collected, $200 owed". The Stripe *fee* has no such
        -- fallback (it's unknowable without the balance transaction), so it
        -- stays NULL until the row syncs.
        COALESCE(so.amount, c.payment_amount)      AS stripe_amount,
        so.stripe_fee,
        so.paid_at                                 AS stripe_paid_at,
        so.discount_code,
        -- ADR-046. "stripe" = patient paid via Stripe; "corporate" =
        -- employer-paid, no Stripe row but doctor IS owed; "test" =
        -- /prueba bypass, excluded by the WHERE clause below.
        COALESCE(c.payment_source, 'stripe')       AS payment_source,
        c.corporate_account_id                     AS corporate_account_id,
        conv.tenant                                AS tenant,
        -- Doctor-share basis: a doctor's own DIRECT patients (conversation
        -- tenant 'direct') pay that doctor's negotiated rate
        -- (consultation_fee_mxn, pesos). HD-sourced MVP — and anything not
        -- 'direct' — pays the flat $100; HD keeps the sourcing margin. A
        -- direct consult with no configured fee falls back to $100.
        (CASE WHEN conv.tenant = 'direct' AND COALESCE(d.consultation_fee_mxn, 0) > 0
              THEN d.consultation_fee_mxn::float8
              ELSE $3::float8 END)                 AS fee_mxn,
        -- Collected / payable, with NO status='completed' gate. See the
        -- @collected_sql module attribute for the full rule (shared with
        -- pay_to_doc below so the two can't drift).
        (
          #{@collected_sql}
        )                                          AS auto_eligible,
        -- Explicit decision wins ("pay anyway" / "skip"); else pay when
        -- collected. So: payment / corporate / free-consult OR pay_doctor=true.
        COALESCE(
          cpd.pay_doctor,
          (
            #{@collected_sql}
          )
        )                                          AS pay_to_doc,
        cpd.pay_doctor                             AS pay_doctor_override,
        (pa.cid IS NOT NULL)                       AS is_paid_to_doctor,
        pa.payout_date                             AS payout_date,
        COALESCE(ROUND(pa.amount_cents / 100.0, 2)::float8, 0::float8) AS paid_out_amount,
        COALESCE(ROUND(pa.iva_cents / 100.0, 2)::float8, 0::float8)    AS iva_retentions_applied,
        COALESCE(ROUND(pa.isr_cents / 100.0, 2)::float8, 0::float8)    AS isr_retentions_applied
      FROM consultations c
      LEFT JOIN doctors  d  ON d.id = c.doctor_id
      LEFT JOIN patients pt ON pt.id = c.patient_id
      LEFT JOIN conversations conv ON conv.id = c.conversation_id
      LEFT JOIN consultation_payout_decisions cpd ON cpd.consultation_id = c.id
      LEFT JOIN pay_agg    pa ON pa.cid = c.id
      LEFT JOIN stripe_one so ON so.cid = c.id
      WHERE ($1::timestamp IS NULL OR c.completed_at >= $1::timestamp)
        AND ($2::timestamp IS NULL OR c.completed_at < $2::timestamp)
        -- ADR-046: /prueba test bypass rows are not doctor-payable; hide them.
        AND COALESCE(c.payment_source, 'stripe') <> 'test'
        AND (pt.id IS DISTINCT FROM $7)
        AND (d.id  IS DISTINCT FROM $8)
    ),
    main AS (
      SELECT
        base.*,
        (CASE WHEN pay_to_doc THEN fee_mxn ELSE 0::float8 END) AS doctor_share,
        -- HD commission = gross above the doctor's share. NULL with no
        -- Stripe row; can go negative when a promo drops price below fee.
        (stripe_amount - fee_mxn)                              AS hd_commission,
        $4::float8                                             AS iva_retention_to_apply,
        -- Retention only applies to a payment we're actually making. With
        -- pay_to_doc = false there's no honorario, so no ISR to withhold —
        -- otherwise a not-paid consultation would post a phantom negative.
        (CASE WHEN NOT pay_to_doc THEN 0::float8
              WHEN has_correct_rfc THEN $5::float8
              ELSE $6::float8 END)                             AS isr_retention_to_apply
      FROM base
    )
    SELECT
      main.*,
      -- Gross still owed the doctor, net of BOTH cash already sent AND tax
      -- already withheld on their behalf. A retention settles part of the
      -- gross share exactly like cash does (share = cash + withholding), so it
      -- must be subtracted here. Without the applied-retention terms, a
      -- fully-paid consult shows a phantom balance equal to the withheld ISR.
      (doctor_share - paid_out_amount
       - iva_retentions_applied - isr_retentions_applied) AS owed_to_doctor,
      -- Net CASH still to send = the doctor's after-tax target
      -- (share − retentions due) minus cash already paid.
      ((doctor_share - iva_retention_to_apply - isr_retention_to_apply)
       - paid_out_amount)                               AS net_payment_pending
    FROM main
    ORDER BY doctor_name ASC, completed_at ASC
    """

    params = [
      start_naive,
      end_exclusive,
      @doctor_share_mxn,
      @iva_rate_pct,
      @isr_rate_with_rfc_pct,
      @isr_rate_without_rfc_pct,
      @test_patient_id,
      @test_doctor_id
    ]

    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, params)
    columns = Enum.map(result.columns, &String.to_atom/1)

    result.rows
    |> Enum.map(fn row -> columns |> Enum.zip(row) |> Map.new() end)
    |> Enum.map(&round_money/1)
  end

  # Postgres returns numeric and float8 a mix of Decimal and float
  # depending on the operation. Normalize money columns to 2-decimal
  # floats so display + filter math is consistent.
  defp round_money(row) do
    row
    |> Map.update!(:doctor_share, &to_round/1)
    |> Map.update!(:iva_retention_to_apply, &to_round/1)
    |> Map.update!(:isr_retention_to_apply, &to_round/1)
    |> Map.update!(:paid_out_amount, &to_round/1)
    |> Map.update!(:iva_retentions_applied, &to_round/1)
    |> Map.update!(:isr_retentions_applied, &to_round/1)
    |> Map.update!(:owed_to_doctor, &to_round/1)
    |> Map.update!(:net_payment_pending, &to_round/1)
    |> Map.put(:stripe_amount, round_or_nil(row[:stripe_amount]))
    |> Map.put(:stripe_fee, round_or_nil(row[:stripe_fee]))
    |> Map.put(:hd_commission, round_or_nil(row[:hd_commission]))
  end

  defp to_round(v), do: v |> to_float() |> Float.round(2)

  # ── Per-doctor aggregation ─────────────────────────────────────

  defp aggregate_by_doctor(consultations) do
    consultations
    |> Enum.group_by(& &1.doctor_id)
    |> Enum.map(fn {doctor_id, rows} ->
      sample = List.first(rows)
      rated = Enum.filter(rows, &is_integer(&1.patient_rating))
      rated_count = length(rated)

      avg_rating =
        if rated_count > 0 do
          sum = Enum.reduce(rated, 0, &(&2 + &1.patient_rating))
          Float.round(sum / rated_count, 2)
        end

      %{
        doctor_id: doctor_id,
        doctor_name: sample.doctor_name || "—",
        doctor_specialty: sample.doctor_specialty,
        has_correct_rfc: sample.has_correct_rfc,
        consultations: length(rows),
        direct_count: Enum.count(rows, &(&1.tenant == "direct")),
        paid_to_doctor_count: Enum.count(rows, & &1.is_paid_to_doctor),
        skipped_count: Enum.count(rows, &(&1.pay_to_doc == false)),
        stripe_amount: sum_round_nilable(rows, :stripe_amount),
        stripe_fee: sum_round_nilable(rows, :stripe_fee),
        doctor_share: sum_round(rows, :doctor_share),
        hd_commission: sum_round_nilable(rows, :hd_commission),
        paid_out_amount: sum_round(rows, :paid_out_amount),
        iva_retention_to_apply: sum_round(rows, :iva_retention_to_apply),
        isr_retention_to_apply: sum_round(rows, :isr_retention_to_apply),
        iva_retentions_applied: sum_round(rows, :iva_retentions_applied),
        isr_retentions_applied: sum_round(rows, :isr_retentions_applied),
        owed_to_doctor: sum_round(rows, :owed_to_doctor),
        net_payment_pending: sum_round(rows, :net_payment_pending),
        avg_rating: avg_rating,
        rated_count: rated_count
      }
    end)
    |> Enum.sort_by(& &1.net_payment_pending, :desc)
  end

  defp totals(consultations, per_doctor) do
    rated = Enum.filter(consultations, &is_integer(&1.patient_rating))
    rated_count = length(rated)

    avg_rating =
      if rated_count > 0 do
        sum = Enum.reduce(rated, 0, &(&2 + &1.patient_rating))
        Float.round(sum / rated_count, 2)
      end

    %{
      total_consultations: length(consultations),
      direct_count: Enum.count(consultations, &(&1.tenant == "direct")),
      paid_to_doctor_count: Enum.count(consultations, & &1.is_paid_to_doctor),
      unique_doctors: length(per_doctor),
      total_stripe_amount: sum_round_nilable(consultations, :stripe_amount),
      total_stripe_fee: sum_round_nilable(consultations, :stripe_fee),
      total_doctor_share: sum_round(consultations, :doctor_share),
      total_hd_commission: sum_round_nilable(consultations, :hd_commission),
      total_paid_out: sum_round(consultations, :paid_out_amount),
      total_iva_to_apply: sum_round(consultations, :iva_retention_to_apply),
      total_isr_to_apply: sum_round(consultations, :isr_retention_to_apply),
      total_iva_applied: sum_round(consultations, :iva_retentions_applied),
      total_isr_applied: sum_round(consultations, :isr_retentions_applied),
      total_owed_to_doctor: sum_round(consultations, :owed_to_doctor),
      total_net_payment_pending: sum_round(consultations, :net_payment_pending),
      avg_rating: avg_rating,
      rated_count: rated_count
    }
  end

  defp sum_round(rows, key) do
    rows
    |> Enum.reduce(0.0, fn r, acc -> acc + to_float(Map.get(r, key)) end)
    |> Float.round(2)
  end

  # Sum but ignore nil values (e.g. hd_commission is nil when no Stripe
  # payment exists — don't count those as zero, which would be wrong;
  # treat as missing).
  defp sum_round_nilable(rows, key) do
    rows
    |> Enum.reduce(0.0, fn r, acc ->
      case Map.get(r, key) do
        nil -> acc
        v -> acc + to_float(v)
      end
    end)
    |> Float.round(2)
  end

  # ── CSV export ─────────────────────────────────────────────────

  def to_csv(%{
        consultations: consultations,
        per_doctor: per_doctor,
        period: {s, e},
        totals: t,
        include_settled?: include_settled?
      }) do
    period_label = "#{s} to #{e}"

    consult_header = [
      "Consultation ID",
      "Completed at",
      "Doctor",
      "Specialty",
      "RFC verified",
      "Patient",
      "Type",
      "Duration (min)",
      "Consultation status",
      "Payment source",
      "Stripe payment status",
      "Stripe amount",
      "Stripe fee",
      "HD commission",
      "Pay doctor?",
      "Doctor share (MXN)",
      "IVA retention to apply",
      "ISR retention to apply",
      "Paid out (MXN)",
      "IVA retentions applied",
      "ISR retentions applied",
      "Owed to doctor (MXN)",
      "Net payment pending (MXN)",
      "Payout date",
      "Paid to doctor?",
      "Rating"
    ]

    consult_rows =
      Enum.map(consultations, fn r ->
        [
          r.consultation_id,
          format_naive(r.completed_at),
          r.doctor_name || "",
          r.doctor_specialty || "",
          yes_no(r.has_correct_rfc),
          r.patient_name || "",
          r.consultation_type || "",
          r.duration_minutes,
          r.consultation_status || "",
          r.payment_source || "",
          r.payment_status || "",
          r.stripe_amount,
          r.stripe_fee,
          r.hd_commission,
          yes_no(r.pay_to_doc),
          r.doctor_share,
          r.iva_retention_to_apply,
          r.isr_retention_to_apply,
          r.paid_out_amount,
          r.iva_retentions_applied,
          r.isr_retentions_applied,
          r.owed_to_doctor,
          r.net_payment_pending,
          r.payout_date,
          yes_no(r.is_paid_to_doctor),
          r.patient_rating
        ]
      end)

    doctor_header = [
      "Doctor",
      "Specialty",
      "RFC verified",
      "Consultations",
      "Paid to doctor",
      "Doctor share (MXN)",
      "HD commission (MXN)",
      "Paid out (MXN)",
      "ISR to apply",
      "ISR applied",
      "Owed to doctor",
      "Net payment pending",
      "Avg rating",
      "# rated"
    ]

    doctor_rows =
      Enum.map(per_doctor, fn r ->
        [
          r.doctor_name,
          r.doctor_specialty || "",
          yes_no(r.has_correct_rfc),
          r.consultations,
          r.paid_to_doctor_count,
          r.doctor_share,
          r.hd_commission,
          r.paid_out_amount,
          r.isr_retention_to_apply,
          r.isr_retentions_applied,
          r.owed_to_doctor,
          r.net_payment_pending,
          r.avg_rating,
          r.rated_count
        ]
      end)

    scope_line =
      if include_settled?,
        do: "All rows (incl. net pending = 0).",
        else: "Only rows with net payment pending ≠ 0."

    sections = [
      [
        ["HelloDoctor — Monthly Doctor Payout Report"],
        ["Period", "#{s}", "to", "#{e}"],
        ["Scope", scope_line],
        []
      ],
      [
        ["Consultations — period #{period_label}"],
        consult_header | consult_rows
      ],
      [[]],
      [
        ["Per-doctor summary — period #{period_label}"],
        doctor_header | doctor_rows
      ],
      [[]],
      [
        ["Totals — period #{period_label}"],
        ["Consultations", t.total_consultations],
        ["Paid to doctor (count)", t.paid_to_doctor_count],
        ["Unique doctors", t.unique_doctors],
        ["Doctor share total (MXN)", t.total_doctor_share],
        ["HD commission total (MXN)", t.total_hd_commission],
        ["Paid out total (MXN)", t.total_paid_out],
        ["IVA to apply total", t.total_iva_to_apply],
        ["ISR to apply total", t.total_isr_to_apply],
        ["IVA applied total", t.total_iva_applied],
        ["ISR applied total", t.total_isr_applied],
        ["Owed to doctor (MXN)", t.total_owed_to_doctor],
        ["Net payment pending (MXN)", t.total_net_payment_pending],
        ["Average patient rating", t.avg_rating],
        ["# consultations rated", t.rated_count]
      ]
    ]

    sections
    |> Enum.concat()
    |> Enum.map_join("", &encode_row/1)
  end

  # ── XLSX export (2 sheets: Resumen + Detalle) ──────────────────

  @doc """
  Builds the report as a native `.xlsx` binary with two sheets:

    * `Resumen`  — one row per doctor (the payout order list).
    * `Detalle`  — one row per consultation (the audit trail).

  Mirrors the spreadsheet ops keeps by hand. Returns the raw binary.
  """
  def to_xlsx(%{consultations: consultations, per_doctor: per_doctor}) do
    resumen_header = [
      "doctor_id",
      "Doctor",
      "Especialidad",
      "RFC ok",
      "Consultas",
      "Directas",
      "$ consultas (cobrado)",
      "Comisión HD",
      "Monto Doc",
      "Costo Stripe",
      "Retención IVA",
      "Retención ISR",
      "Ya pagado",
      "Ya retenido IVA",
      "Ya retenido ISR",
      "Pago pendiente",
      "Rating prom"
    ]

    resumen_rows =
      Enum.map(per_doctor, fn d ->
        [
          d.doctor_id,
          d.doctor_name,
          d.doctor_specialty || "",
          yes_no(d.has_correct_rfc),
          d.consultations,
          d.direct_count,
          cell(d.stripe_amount),
          cell(d.hd_commission),
          d.doctor_share,
          cell(d.stripe_fee),
          d.iva_retention_to_apply,
          d.isr_retention_to_apply,
          d.paid_out_amount,
          d.iva_retentions_applied,
          d.isr_retentions_applied,
          d.net_payment_pending,
          cell(d.avg_rating)
        ]
      end)

    detalle_header = [
      "consultation_id",
      "completed_at",
      "doctor_id",
      "Doctor",
      "Especialidad",
      "Tenant",
      "Tipo",
      "Duración (min)",
      "Estado consulta",
      "Paciente",
      "Estado pago (Stripe)",
      "Código descuento",
      "$ Stripe",
      "Costo Stripe",
      "Comisión HD",
      "¿Pagar al doctor?",
      "Monto Doc",
      "Retención IVA",
      "Retención ISR",
      "Ya pagado",
      "Ya retenido IVA",
      "Ya retenido ISR",
      "Adeudo",
      "Pago pendiente",
      "Fecha pago",
      "¿Pagado?",
      "Rating"
    ]

    detalle_rows =
      Enum.map(consultations, fn r ->
        [
          r.consultation_id,
          cell(r.completed_at),
          r.doctor_id,
          r.doctor_name || "",
          r.doctor_specialty || "",
          r.tenant || "",
          r.consultation_type || "",
          cell(r.duration_minutes),
          r.consultation_status || "",
          r.patient_name || "",
          r.payment_status || "",
          r.discount_code || "",
          cell(r.stripe_amount),
          cell(r.stripe_fee),
          cell(r.hd_commission),
          yes_no(r.pay_to_doc),
          r.doctor_share,
          r.iva_retention_to_apply,
          r.isr_retention_to_apply,
          r.paid_out_amount,
          r.iva_retentions_applied,
          r.isr_retentions_applied,
          r.owed_to_doctor,
          r.net_payment_pending,
          cell(r.payout_date),
          yes_no(r.is_paid_to_doctor),
          cell(r.patient_rating)
        ]
      end)

    workbook = %Workbook{
      sheets: [
        %Sheet{name: "Resumen", rows: [resumen_header | resumen_rows]},
        %Sheet{name: "Detalle", rows: [detalle_header | detalle_rows]}
      ]
    }

    {:ok, {_filename, binary}} = Elixlsx.write_to_memory(workbook, "payouts.xlsx")
    binary
  end

  # Coerce a value into something Elixlsx can write: dates → ISO strings,
  # nil → "", numbers/strings pass through.
  defp cell(nil), do: ""
  defp cell(%Date{} = d), do: Date.to_iso8601(d)
  defp cell(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_string(ndt)
  defp cell(%DateTime{} = dt), do: DateTime.to_string(dt)
  defp cell(v), do: v

  defp encode_row(row) when is_list(row) do
    row
    |> Enum.map(&csv_field/1)
    |> Enum.join(",")
    |> Kernel.<>("\r\n")
  end

  defp csv_field(nil), do: ""
  defp csv_field(v) when is_integer(v) or is_float(v), do: to_string(v)

  defp csv_field(%Date{} = d), do: Date.to_iso8601(d)
  defp csv_field(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_string(ndt)

  defp csv_field(v) when is_binary(v) do
    if String.contains?(v, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(v, "\"", "\"\"")}")
    else
      v
    end
  end

  defp csv_field(other), do: csv_field(to_string(other))

  # ── Misc helpers ───────────────────────────────────────────────

  defp format_naive(nil), do: ""
  defp format_naive(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_string(ndt)

  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"
  defp yes_no(_), do: ""

  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(n) when is_float(n), do: n

  defp round_or_nil(nil), do: nil
  defp round_or_nil(v), do: v |> to_float() |> Float.round(2)

  def doctor_share_per_consultation, do: @doctor_share_mxn
end
