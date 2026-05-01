defmodule Ledgr.Core.Expenses.Expense do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Accounting.Account

  schema "expenses" do
    field :date, :date
    field :description, :string
    field :amount_cents, :integer
    field :category, :string
    field :iva_cents, :integer, default: 0
    field :payee, :string

    belongs_to :expense_account, Account
    belongs_to :paid_from_account, Account

    timestamps()
  end

  @required_fields ~w(date description amount_cents expense_account_id paid_from_account_id)a
  @optional_fields ~w(category iva_cents payee)a

  def changeset(expense, attrs) do
    expense
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_number(:iva_cents, greater_than_or_equal_to: 0)
    |> assoc_constraint(:expense_account)
    |> assoc_constraint(:paid_from_account)
  end
end
