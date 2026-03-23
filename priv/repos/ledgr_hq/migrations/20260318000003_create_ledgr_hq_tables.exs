defmodule Ledgr.Repos.LedgrHQ.Migrations.CreateLedgrHQTables do
  use Ecto.Migration

  @moduledoc """
  Ledgr HQ domain-specific tables:
  - subscription_plans  (tiers ledgr offers to clients)
  - clients             (businesses using ledgr)
  - client_subscriptions (which client is on which plan)
  - costs               (recurring operational costs)
  """

  def change do
    # ── Subscription Plans ───────────────────────────────────
    create table(:subscription_plans) do
      add :name, :string, null: false
      add :description, :text
      add :price_cents, :integer, null: false
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    # ── Clients ──────────────────────────────────────────────
    create table(:clients) do
      add :name, :string, null: false
      add :domain_slug, :string
      add :status, :string, null: false, default: "active"  # active | trial | paused | churned
      add :started_on, :date, null: false
      add :ended_on, :date
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:clients, [:status])
    create index(:clients, [:domain_slug])

    # ── Client Subscriptions ─────────────────────────────────
    create table(:client_subscriptions) do
      add :client_id, references(:clients, on_delete: :restrict), null: false
      add :subscription_plan_id, references(:subscription_plans, on_delete: :restrict), null: false
      add :starts_on, :date, null: false
      add :ends_on, :date
      add :status, :string, null: false, default: "active"  # active | trial | cancelled
      add :price_override_cents, :integer
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:client_subscriptions, [:client_id])
    create index(:client_subscriptions, [:subscription_plan_id])
    create index(:client_subscriptions, [:status])

    # ── Costs ────────────────────────────────────────────────
    create table(:costs) do
      add :name, :string, null: false
      add :vendor, :string
      add :category, :string, null: false  # cloud_hosting | domain_dns | saas_tools
      add :amount_cents, :integer, null: false
      add :billing_period, :string, null: false, default: "monthly"  # monthly | annual | one_time
      add :active, :boolean, default: true, null: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:costs, [:active])
    create index(:costs, [:category])
  end
end
