defmodule Ledgr.Repos.CasaTame.Migrations.CreateExpenseRefunds do
  use Ecto.Migration

  def up do
    create table(:expense_refunds) do
      add :expense_id,           references(:expenses, on_delete: :delete_all), null: false
      add :date,                 :date,    null: false
      add :amount_cents,         :integer, null: false
      add :currency,             :string,  null: false
      add :refund_to_account_id, references(:accounts, on_delete: :restrict), null: false
      add :reason,               :text

      timestamps()
    end

    create index(:expense_refunds, [:expense_id])
    create index(:expense_refunds, [:date])

    create constraint(:expense_refunds, :positive_amount,
      check: "amount_cents > 0"
    )

    create constraint(:expense_refunds, :valid_currency,
      check: "currency IN ('USD', 'MXN')"
    )
  end

  def down do
    drop table(:expense_refunds)
  end
end
