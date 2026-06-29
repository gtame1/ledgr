defmodule Ledgr.Domains.HelloDoctor.ConsultationPayouts do
  @moduledoc """
  Frozen-at-delivery snapshot of the doctor share earned per consultation.

  The share is **tenant-aware** (same rule as `MonthlyReport` /
  `ConsultationAccounting.doctor_share_mxn/2`): a doctor's own DIRECT
  patients pay that doctor's `consultation_fee_mxn`; MVP/other pay the flat
  share. We materialize it into the Ledgr-owned `consultation_payouts`
  table so it can be read per-consultation and so the amount is **pinned at
  delivery** — once a row exists we never rewrite its `doctor_share_cents`,
  so a later fee change leaves history untouched.

  Split of concerns:

    * **earned** (this table) — frozen share. One row per billed, non-test
      consultation.
    * **payable** (`ConsultationPayoutDecisions`) — the mutable operator
      decision of whether we actually pay it. `net = if pay_doctor?, do:
      earned, else: 0`, derived live.

  Populated by `ConsultationPayoutsWorker` (boot + daily) via `recompute/0`,
  and lazily by `ensure_frozen/1` when a consultation page is viewed before
  the next sweep. Inserts use `ON CONFLICT DO NOTHING`, so they're idempotent
  and never clobber a frozen amount.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting
  alias Ledgr.Domains.HelloDoctor.ConsultationPayouts.ConsultationPayout
  alias Ledgr.Domains.HelloDoctor.TestAccounts

  @doc "Flat doctor share per consultation, in centavos (the MVP default)."
  def share_cents, do: ConsultationAccounting.doctor_share_cents()

  @doc """
  Freezes the (tenant-aware) doctor share for every billed, non-test
  consultation that doesn't already have a row, and prunes any rows that are
  now test accounts. Returns the number of newly-frozen rows.
  """
  def recompute do
    %{num_rows: inserted} = Ecto.Adapters.SQL.query!(Repo.active_repo(), freeze_sql(""), [])

    # Drop rows that are now classified as test accounts (snapshot hygiene).
    Ecto.Adapters.SQL.query!(
      Repo.active_repo(),
      "DELETE FROM consultation_payouts cp WHERE #{TestAccounts.is_test_patient_sql("cp.patient_id")}",
      []
    )

    inserted
  end

  @doc "Stored frozen payout for one consultation, or `nil`."
  def get(consultation_id) when is_binary(consultation_id) do
    Repo.get_by(ConsultationPayout, consultation_id: consultation_id)
  end

  @doc """
  Returns `%{consultation_id => %ConsultationPayout{}}` for the given ids.
  """
  def map(consultation_ids) when is_list(consultation_ids) do
    from(cp in ConsultationPayout, where: cp.consultation_id in ^consultation_ids)
    |> Repo.all()
    |> Map.new(&{&1.consultation_id, &1})
  end

  @doc """
  Returns the frozen row for `consultation_id`, freezing it first if it's a
  billed, non-test consultation with no row yet. Returns `nil` for
  consultations that aren't doctor-payable (test/bypass, unpaid).
  """
  def ensure_frozen(consultation_id) when is_binary(consultation_id) do
    case get(consultation_id) do
      %ConsultationPayout{} = row ->
        row

      nil ->
        Ecto.Adapters.SQL.query!(
          Repo.active_repo(),
          freeze_sql("AND c.id = $1"),
          [consultation_id]
        )

        get(consultation_id)
    end
  end

  # INSERT … SELECT that freezes the tenant-aware share for the billed,
  # non-test population. `extra_where` lets the lazy path scope to one id.
  defp freeze_sql(extra_where) do
    share = ConsultationAccounting.doctor_share_sql("conv.tenant", "d.consultation_fee_mxn")

    """
    INSERT INTO consultation_payouts
      (consultation_id, doctor_id, doctor_share_cents, payment_source, computed_at, inserted_at, updated_at)
    SELECT
      c.id,
      c.doctor_id,
      ROUND(#{share} * 100)::int,
      COALESCE(c.payment_source, 'stripe'),
      NOW(), NOW(), NOW()
    FROM consultations c
    LEFT JOIN conversations conv ON conv.id = c.conversation_id
    LEFT JOIN doctors d ON d.id = c.doctor_id
    WHERE c.payment_status IN ('paid', 'confirmed', 'refunded')
      AND COALESCE(c.payment_source, 'stripe') <> 'test'
      AND (
        EXISTS (
          SELECT 1 FROM stripe_payments sp
          WHERE sp.consultation_id = c.id
             OR (sp.consultation_id IS NULL
                 AND c.stripe_payment_intent_id IS NOT NULL
                 AND sp.stripe_payment_intent_id = c.stripe_payment_intent_id)
        )
        OR (c.payment_amount IS NOT NULL AND c.payment_amount >= 0)
      )
      AND #{TestAccounts.not_test_patient_sql("c.patient_id")}
      #{extra_where}
    ON CONFLICT (consultation_id) DO NOTHING
    """
  end
end
