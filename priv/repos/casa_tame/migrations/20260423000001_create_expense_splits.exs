defmodule Ledgr.Repos.CasaTame.Migrations.CreateExpenseSplits do
  use Ecto.Migration

  def up do
    create table(:expense_splits) do
      add :expense_id, references(:expenses, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :amount_cents, :integer, null: false

      timestamps()
    end

    create index(:expense_splits, [:expense_id])
  end

  def down do
    drop table(:expense_splits)
  end
end
