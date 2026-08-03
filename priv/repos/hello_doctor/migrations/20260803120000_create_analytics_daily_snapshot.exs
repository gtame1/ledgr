defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateAnalyticsDailySnapshot do
  use Ecto.Migration

  @moduledoc """
  Ledgr-owned daily snapshot of HD headline numbers — layer 1 of
  `docs/design/reporting-architecture.md`.

  This exists to solve a data-loss problem, not to serve a dashboard. The bot
  hard-deletes old conversations and messages, so historical counts read from
  the live tables are retroactively unreproducible: last month's number changes
  depending on when you ask. Nothing in Ledgr deletes, and Neon PITR is only
  24h, so the only durable fix is to write the numbers down as they happen.

  Consequences of that purpose:

    * The bot never touches this table. It is ours.
    * Over-capture. A column not snapshotted today cannot be backfilled once
      the underlying rows are gone — hence the `breakdowns` jsonb, which lets
      new cuts be added without a migration.
    * Dates are Mexico-local (`snapshot_date`), matching every HD report.

  Counts exclude test traffic (`analytics.fct_consultation.is_test` and the
  equivalent patient-phone predicate), so a snapshot row means what the
  business means.
  """

  def change do
    create table(:analytics_daily_snapshot) do
      add :snapshot_date, :date, null: false

      # ── Consultations, from analytics.fct_consultation (completed_at_mx) ──
      add :consults_completed, :integer, null: false, default: 0
      add :consults_paid, :integer, null: false, default: 0
      add :consults_comped, :integer, null: false, default: 0
      add :consults_refunded, :integer, null: false, default: 0
      add :consults_collected, :integer, null: false, default: 0
      add :consults_direct, :integer, null: false, default: 0
      add :consults_corporate, :integer, null: false, default: 0
      # Excluded from every other count on this row; kept so QA volume is
      # visible rather than invisible.
      add :consults_test, :integer, null: false, default: 0
      add :doctors_active, :integer, null: false, default: 0

      # ── Money, MXN ──
      add :gross_mxn, :float, null: false, default: 0.0
      add :doctor_share_mxn, :float, null: false, default: 0.0
      # gross - doctor_share. Negative on comp-heavy days by design.
      add :hd_commission_mxn, :float, null: false, default: 0.0

      # ── The evaporating tables. These are the whole point. ──
      add :conversations_created, :integer, null: false, default: 0
      add :conversations_paid, :integer, null: false, default: 0
      add :messages_sent, :integer, null: false, default: 0
      add :patients_created, :integer, null: false, default: 0

      # Histograms (payment_status, consultation_type, tenant, funnel_stage).
      # jsonb so a new cut needs no migration — see "over-capture" above.
      add :breakdowns, :map, null: false, default: %{}

      # When this row was computed. A row recomputed days later (late payment
      # confirmation) will have a computed_at well after its snapshot_date.
      add :computed_at, :naive_datetime, null: false

      timestamps()
    end

    # One row per day; the writer upserts on this.
    create unique_index(:analytics_daily_snapshot, [:snapshot_date])
  end
end
