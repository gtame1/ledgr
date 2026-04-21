defmodule Ledgr.Repos.AumentaMiPension.Migrations.CreateAccountingTables do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:accounts) do
      add :code, :string, null: false
      add :name, :string, null: false
      add :type, :string, null: false
      add :normal_balance, :string, null: false
      add :is_cash, :boolean, default: false
      add :is_cogs, :boolean, default: false
      timestamps()
    end

    create_if_not_exists unique_index(:accounts, [:code])

    create_if_not_exists table(:journal_entries) do
      add :date, :date, null: false
      add :description, :string, null: false
      add :entry_type, :string
      add :reference, :string
      add :payee, :string
      timestamps()
    end

    create_if_not_exists table(:journal_lines) do
      add :journal_entry_id, references(:journal_entries, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :debit_cents, :integer, default: 0
      add :credit_cents, :integer, default: 0
      add :description, :string
      timestamps()
    end

    create_if_not_exists index(:journal_lines, [:journal_entry_id])
    create_if_not_exists index(:journal_lines, [:account_id])
  end
end
