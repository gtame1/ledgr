defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateMarketingCosts do
  use Ecto.Migration

  @moduledoc """
  Ledgr-owned table for marketing / ad spend (Meta, Google, …).

  Fed by periodic CSV upload today (an API sync can populate the same table
  later — hence `source`). Each row posts a balanced journal entry
  (DEBIT 6050 Marketing & Advertising / CREDIT 2310 Accounts Payable —
  Marketing), so the P&L and the dashboard CAC are complete.

  Spend is uploaded per platform + date (optionally in USD); `campaign_id` is
  reserved for future per-campaign attribution and is unused for now.
  """

  def change do
    create table(:marketing_costs) do
      add :platform, :string, null: false
      add :date, :date, null: false
      # Amount as uploaded, in `currency`. `spend_mxn_cents` is the posted MXN.
      add :amount, :float, null: false, default: 0.0
      add :currency, :string, null: false, default: "MXN"
      add :fx_rate, :float
      add :spend_mxn_cents, :integer
      add :description, :string
      # "csv" today; "meta" / "google" when an API sync lands.
      add :source, :string, null: false, default: "csv"
      # Reserved for future per-campaign spend; NULL = platform-level total.
      add :campaign_id, :string
      # GL posting stamps.
      add :posted_at, :utc_datetime
      add :journal_entry_id, :integer

      timestamps()
    end

    # One platform-level total per platform/date/source…
    create unique_index(:marketing_costs, [:platform, :date, :source],
             where: "campaign_id IS NULL",
             name: :marketing_costs_platform_date_source_idx
           )

    # …and, when per-campaign spend is used later, one per campaign too.
    create unique_index(:marketing_costs, [:platform, :date, :source, :campaign_id],
             where: "campaign_id IS NOT NULL",
             name: :marketing_costs_platform_date_source_campaign_idx
           )

    create index(:marketing_costs, [:date])
  end
end
