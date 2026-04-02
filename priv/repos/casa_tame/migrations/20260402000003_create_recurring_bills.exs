defmodule Ledgr.Repos.CasaTame.Migrations.CreateRecurringBills do
  use Ecto.Migration

  def change do
    create table(:recurring_bills) do
      add :name, :string, null: false
      add :amount_cents, :integer
      add :currency, :string, size: 3, null: false, default: "MXN"
      add :frequency, :string, null: false
      add :day_of_month, :integer
      add :next_due_date, :date, null: false
      add :category, :string
      add :notes, :text
      add :is_active, :boolean, default: true, null: false

      timestamps()
    end

    create index(:recurring_bills, [:next_due_date])
    create index(:recurring_bills, [:is_active])
  end
end
