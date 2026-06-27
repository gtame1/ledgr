defmodule Ledgr.Domains.HelloDoctor.ConsultationPayouts do
  @moduledoc """
  Frozen-at-delivery snapshot of the doctor share earned per consultation.

  The amount the doctor earns is computed by the *same* logic the Doctor
  Payouts page uses (`DoctorPayouts.list_consultations_with_payouts/3`):
  a flat `ConsultationAccounting.doctor_share_mxn/0` for every billed,
  non-test consultation. We materialize it into the Ledgr-owned
  `consultation_payouts` table so it can be read per-consultation and so
  the rate is **pinned at delivery** — once a row exists we never rewrite
  its `doctor_share_cents`, so a future change to the flat share leaves
  history untouched.

  Note the split of concerns:

    * **earned** (this table) — frozen gross share, $100 at the rate of the
      day. One row per billed consultation.
    * **payable** (`ConsultationPayoutDecisions`) — the mutable operator
      decision of whether we actually pay it. `net = if pay_doctor?, do:
      earned, else: 0`, derived live.

  Populated by `ConsultationPayoutsWorker` (boot + daily) via `recompute/0`,
  and lazily by `ensure_frozen/1` when a consultation page is viewed before
  the next sweep. Both insert with `ON CONFLICT DO NOTHING`, so they're
  idempotent and never clobber a frozen amount.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
  alias Ledgr.Domains.HelloDoctor.DoctorPayouts
  alias Ledgr.Domains.HelloDoctor.ConsultationPayouts.ConsultationPayout

  # Mirrors DoctorPayouts.@payable_statuses — used only by the single-row
  # lazy-freeze gate. The bulk recompute reuses the report query directly.
  @payable_statuses ~w[paid confirmed refunded]

  # All-time window for the bulk sweep.
  @epoch ~D[2000-01-01]
  @far_future ~D[2100-01-01]

  @doc "Flat doctor share per consultation, in centavos (the frozen rate)."
  def share_cents, do: ConsultationAccounting.doctor_share_cents()

  @doc """
  Freezes the doctor share for every billed, non-test consultation that
  doesn't already have a row. Returns the number of newly-frozen rows.
  """
  def recompute do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      DoctorPayouts.list_consultations_with_payouts(@epoch, @far_future, status: :all)
      |> Enum.uniq_by(& &1.consultation_id)
      |> Enum.reject(&is_nil(&1.consultation_id))
      |> Enum.map(&row_attrs(&1.consultation_id, &1.doctor_id, &1.payment_source, now))

    {inserted, _} =
      Repo.insert_all(ConsultationPayout, entries,
        on_conflict: :nothing,
        conflict_target: :consultation_id
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
        with %Consultation{} = c <- Repo.get(Consultation, consultation_id),
             true <- payable_population?(c) do
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          Repo.insert_all(
            ConsultationPayout,
            [row_attrs(c.id, c.doctor_id, c.payment_source, now)],
            on_conflict: :nothing,
            conflict_target: :consultation_id
          )

          get(consultation_id)
        else
          _ -> nil
        end
    end
  end

  # A consultation is in the doctor-payable population when it's billed and
  # not a /prueba test/bypass row. Mirrors the report's gate closely enough
  # for the lazy path; the daily recompute is canonical.
  defp payable_population?(%Consultation{} = c) do
    c.payment_status in @payable_statuses and
      (c.payment_source || "stripe") != "test" and
      not is_nil(c.payment_amount)
  end

  defp row_attrs(consultation_id, doctor_id, payment_source, now) do
    %{
      consultation_id: consultation_id,
      doctor_id: doctor_id,
      doctor_share_cents: share_cents(),
      payment_source: payment_source || "stripe",
      computed_at: now,
      inserted_at: now,
      updated_at: now
    }
  end
end
