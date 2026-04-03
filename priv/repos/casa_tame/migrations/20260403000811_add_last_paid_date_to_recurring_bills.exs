defmodule Ledgr.Repos.CasaTame.Migrations.AddLastPaidDateToRecurringBills do
  use Ecto.Migration

  def change do
    alter table(:recurring_bills) do
      add :last_paid_date, :date
    end
  end
end
