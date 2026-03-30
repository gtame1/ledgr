defmodule Ledgr.Repos.LedgrHQ.Migrations.AddUniqueIndexesForSeeds do
  use Ecto.Migration

  def change do
    create unique_index(:subscription_plans, [:name])
    create unique_index(:clients, [:name])
    create unique_index(:costs, [:name])
    create unique_index(:client_subscriptions, [:client_id, :subscription_plan_id],
      where: "status != 'cancelled'",
      name: :client_subscriptions_active_unique
    )
  end
end
