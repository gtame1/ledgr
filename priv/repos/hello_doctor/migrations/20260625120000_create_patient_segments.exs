defmodule Ledgr.Repos.HelloDoctor.Migrations.CreatePatientSegments do
  use Ecto.Migration

  @moduledoc """
  Ledgr-owned snapshot of each patient's lifecycle tier (L0–L3).

  The `patients` table is bot-owned, so we keep the tier in our own side
  table (same pattern as consultation_payout_decisions). A recompute job
  materializes it from messages + consultations; the Ledgr UI computes the
  tier live, but this table lets the bot read a patient's tier too.
  """

  def change do
    create table(:patient_segments) do
      add :patient_id, :string, null: false
      # "L0" | "L1" | "L2" | "L3"
      add :tier, :string, null: false
      # The signals the tier was derived from, for transparency.
      add :inbound_messages, :integer, null: false, default: 0
      add :consult_count, :integer, null: false, default: 0
      add :computed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:patient_segments, [:patient_id])
    create index(:patient_segments, [:tier])
  end
end
