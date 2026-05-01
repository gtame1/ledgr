defmodule Ledgr.Repo.Migrations.AddDirectionAndCashAccountToCapitalContributions do
  use Ecto.Migration

  def change do
    alter table(:capital_contributions) do
      add :direction, :string, null: false, default: "in"
    end
  end
end
