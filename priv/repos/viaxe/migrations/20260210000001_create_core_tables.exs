defmodule Ledgr.Repos.Viaxe.Migrations.CreateCoreTables do
  use Ecto.Migration

  @moduledoc """
  Creates all core tables shared across domains:
  accounts, journal_entries, journal_lines, customers, expenses,
  partners, capital_contributions, money_transfers, app_settings.

  These are consolidated from the incremental MrMunchMe migrations
  into the final schema form.
  """

  def change do
    # ── Accounts ─────────────────────────────────────────────
    create table(:accounts) do
      add :code, :string, null: false
      add :name, :string, null: false
      add :type, :string, null: false
      add :normal_balance, :string, null: false
      add :is_cash, :boolean, default: false, null: false
      add :is_cogs, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:accounts, [:code])

    create constraint(:accounts, :normal_balance_check,
      check: "normal_balance IN ('debit','credit')"
    )

    # ── Journal Entries ──────────────────────────────────────
    create table(:journal_entries) do
      add :date, :date, null: false
      add :description, :text, null: false
      add :reference, :string
      add :entry_type, :string, null: false

      timestamps()
    end

    create index(:journal_entries, [:date])
    create index(:journal_entries, [:entry_type])
    create index(:journal_entries, [:entry_type, :date])

    # ── Journal Lines ────────────────────────────────────────
    create table(:journal_lines) do
      add :journal_entry_id, references(:journal_entries, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :description, :string
      add :debit_cents, :integer, default: 0, null: false
      add :credit_cents, :integer, default: 0, null: false

      timestamps()
    end

    create index(:journal_lines, [:journal_entry_id])
    create index(:journal_lines, [:account_id])

    create constraint(:journal_lines, :non_negative_amounts,
      check: "debit_cents >= 0 AND credit_cents >= 0"
    )

    create constraint(:journal_lines, :non_zero_line,
      check: "debit_cents > 0 OR credit_cents > 0"
    )

    # ── Customers ────────────────────────────────────────────
    create table(:customers) do
      add :name, :string
      add :email, :string
      add :phone, :string
      add :delivery_address, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:customers, [:phone])

    # ── Expenses ─────────────────────────────────────────────
    create table(:expenses) do
      add :date, :date, null: false
      add :description, :text, null: false
      add :amount_cents, :integer, null: false
      add :expense_account_id, references(:accounts, on_delete: :restrict), null: false
      add :paid_from_account_id, references(:accounts, on_delete: :restrict), null: false
      add :category, :string

      timestamps()
    end

    create index(:expenses, [:date])
    create index(:expenses, [:expense_account_id])
    create index(:expenses, [:paid_from_account_id])

    # ── Partners & Capital Contributions ─────────────────────
    create table(:partners) do
      add :name, :string, null: false
      add :email, :string
      add :phone, :string

      timestamps()
    end

    create unique_index(:partners, [:email])

    create table(:capital_contributions) do
      add :partner_id, references(:partners, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :amount_cents, :integer, null: false
      add :note, :text
      add :cash_account_id, references(:accounts, on_delete: :nothing)
      add :direction, :string, null: false, default: "in"

      timestamps()
    end

    create index(:capital_contributions, [:partner_id])
    create index(:capital_contributions, [:date])
    create index(:capital_contributions, [:cash_account_id])

    # ── Money Transfers ──────────────────────────────────────
    create table(:money_transfers) do
      add :date, :date, null: false
      add :amount_cents, :integer, null: false
      add :note, :string
      add :from_account_id, references(:accounts, on_delete: :restrict), null: false
      add :to_account_id, references(:accounts, on_delete: :restrict), null: false

      timestamps()
    end

    create index(:money_transfers, [:date])
    create index(:money_transfers, [:from_account_id])
    create index(:money_transfers, [:to_account_id])

    # ── App Settings ─────────────────────────────────────────
    create table(:app_settings) do
      add :key, :string, null: false
      add :value, :string

      timestamps()
    end

    create unique_index(:app_settings, [:key])
  end
end
