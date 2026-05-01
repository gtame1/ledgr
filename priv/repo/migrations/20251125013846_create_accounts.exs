defmodule Ledgr.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :code, :string, null: false
      add :name, :string, null: false
      # asset/liability/equity/revenue/expense
      add :type, :string, null: false
      # debit/credit
      add :normal_balance, :string, null: false
      add :is_cash, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:accounts, [:code])

    create constraint(:accounts, :normal_balance_check,
             check: "normal_balance IN ('debit','credit')"
           )
  end
end
