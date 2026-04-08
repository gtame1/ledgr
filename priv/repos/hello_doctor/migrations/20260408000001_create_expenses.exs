defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateExpenses do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:expenses) do
      add :date, :date, null: false
      add :description, :string, null: false
      add :amount_cents, :integer, null: false
      add :category, :string
      add :iva_cents, :integer, default: 0
      add :payee, :string
      add :expense_account_id, references(:accounts, on_delete: :restrict), null: false
      add :paid_from_account_id, references(:accounts, on_delete: :restrict), null: false

      timestamps()
    end

    create_if_not_exists index(:expenses, [:date])
    create_if_not_exists index(:expenses, [:expense_account_id])
    create_if_not_exists index(:expenses, [:paid_from_account_id])
  end
end
