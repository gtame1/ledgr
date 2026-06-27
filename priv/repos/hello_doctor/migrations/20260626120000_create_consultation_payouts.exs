defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateConsultationPayouts do
  use Ecto.Migration

  @moduledoc """
  Ledgr-owned, frozen-at-delivery snapshot of the doctor share earned per
  consultation.

  `consultations` is bot-owned, so the per-consultation payout amount lives
  in our own side table (same pattern as `consultation_payout_decisions` and
  `patient_segments`). A recompute job inserts a row the first time it sees a
  billed, non-test consultation and **never overwrites it** — so the rate in
  effect at delivery stays pinned even if the flat doctor share changes
  later. What the doctor *earned* is frozen here; whether we actually pay it
  (`pay_doctor`) stays mutable in `consultation_payout_decisions`.
  """

  def change do
    create table(:consultation_payouts) do
      add :consultation_id, :string, null: false
      add :doctor_id, :string
      # Gross doctor share earned, in centavos, at the rate in effect when
      # this row was first frozen. Not adjusted by the pay/don't-pay
      # decision — that's derived live.
      add :doctor_share_cents, :integer, null: false
      # ADR-046 payment source at freeze time: "stripe" | "corporate".
      add :payment_source, :string
      add :computed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:consultation_payouts, [:consultation_id])
    create index(:consultation_payouts, [:doctor_id])
  end
end
