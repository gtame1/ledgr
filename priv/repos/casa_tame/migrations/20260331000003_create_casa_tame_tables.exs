defmodule Ledgr.Repos.CasaTame.Migrations.CreateCasaTameTables do
  use Ecto.Migration

  @moduledoc """
  Creates all Casa Tame domain-specific tables:
  expense categories (hierarchical), income categories, income entries,
  exchange rates, investment accounts/snapshots/transactions,
  debt accounts/snapshots/transactions.

  Also extends the core expenses table with currency and category FK.
  """

  def change do
    # ── Expense Categories (hierarchical) ────────────────────
    create table(:expense_categories) do
      add :name, :string, null: false
      add :parent_id, references(:expense_categories, on_delete: :nilify_all)
      add :icon, :string
      add :is_system, :boolean, default: true, null: false

      timestamps()
    end

    create index(:expense_categories, [:parent_id])
    create unique_index(:expense_categories, [:name, :parent_id], name: :expense_categories_name_parent_unique)

    # ── Income Categories (flat) ─────────────────────────────
    create table(:income_categories) do
      add :name, :string, null: false
      add :icon, :string
      add :is_system, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:income_categories, [:name])

    # ── Income Entries ───────────────────────────────────────
    create table(:income_entries) do
      add :date, :date, null: false
      add :description, :text, null: false
      add :amount_cents, :integer, null: false
      add :currency, :string, size: 3, null: false, default: "MXN"
      add :income_category_id, references(:income_categories, on_delete: :nilify_all)
      add :deposit_account_id, references(:accounts, on_delete: :restrict), null: false
      add :source, :string

      timestamps()
    end

    create index(:income_entries, [:date])
    create index(:income_entries, [:currency])
    create index(:income_entries, [:income_category_id])

    # ── Exchange Rates (daily cache) ─────────────────────────
    create table(:exchange_rates) do
      add :date, :date, null: false
      add :from_currency, :string, size: 3, null: false, default: "USD"
      add :to_currency, :string, size: 3, null: false, default: "MXN"
      add :rate, :decimal, precision: 12, scale: 6, null: false
      add :source, :string, default: "manual"

      timestamps()
    end

    create unique_index(:exchange_rates, [:date, :from_currency, :to_currency])

    # ── Investment Accounts ──────────────────────────────────
    create table(:investment_accounts) do
      add :name, :string, null: false
      add :account_type, :string, null: false
      add :currency, :string, size: 3, null: false, default: "USD"
      add :institution, :string
      add :notes, :text
      add :is_active, :boolean, default: true, null: false

      timestamps()
    end

    # ── Investment Snapshots ─────────────────────────────────
    create table(:investment_snapshots) do
      add :investment_account_id, references(:investment_accounts, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :balance_cents, :bigint, null: false

      timestamps()
    end

    create index(:investment_snapshots, [:investment_account_id])
    create unique_index(:investment_snapshots, [:investment_account_id, :date])

    # ── Investment Transactions ──────────────────────────────
    create table(:investment_transactions) do
      add :investment_account_id, references(:investment_accounts, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :transaction_type, :string, null: false
      add :amount_cents, :bigint, null: false
      add :description, :text

      timestamps()
    end

    create index(:investment_transactions, [:investment_account_id])
    create index(:investment_transactions, [:date])

    # ── Debt Accounts ────────────────────────────────────────
    create table(:debt_accounts) do
      add :name, :string, null: false
      add :account_type, :string, null: false
      add :currency, :string, size: 3, null: false, default: "MXN"
      add :institution, :string
      add :original_amount_cents, :bigint
      add :interest_rate, :decimal, precision: 5, scale: 2
      add :minimum_payment_cents, :integer
      add :notes, :text
      add :is_active, :boolean, default: true, null: false

      timestamps()
    end

    # ── Debt Snapshots ───────────────────────────────────────
    create table(:debt_snapshots) do
      add :debt_account_id, references(:debt_accounts, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :balance_cents, :bigint, null: false

      timestamps()
    end

    create index(:debt_snapshots, [:debt_account_id])
    create unique_index(:debt_snapshots, [:debt_account_id, :date])

    # ── Debt Transactions ────────────────────────────────────
    create table(:debt_transactions) do
      add :debt_account_id, references(:debt_accounts, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :transaction_type, :string, null: false
      add :amount_cents, :bigint, null: false
      add :description, :text

      timestamps()
    end

    create index(:debt_transactions, [:debt_account_id])
    create index(:debt_transactions, [:date])

    # ── Extend Expenses table with currency + category FK ────
    alter table(:expenses) do
      add :currency, :string, size: 3, null: false, default: "MXN"
      add :expense_category_id, references(:expense_categories, on_delete: :nilify_all)
    end

    create index(:expenses, [:currency])
    create index(:expenses, [:expense_category_id])
  end
end
