defmodule Ledgr.Domains.CasaTame.Expenses.ExpenseSplit do
  @moduledoc """
  A single payment leg for a split expense.
  One expense can have many splits, each referencing a payment account and an amount.
  The sum of all split amount_cents equals the parent expense amount_cents.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Accounting.Account

  schema "expense_splits" do
    field :amount_cents, :integer

    belongs_to :expense, Ledgr.Domains.CasaTame.Expenses.CasaTameExpense
    belongs_to :account, Account

    timestamps()
  end

  def changeset(split, attrs) do
    split
    |> cast(attrs, [:expense_id, :account_id, :amount_cents])
    |> validate_required([:account_id, :amount_cents])
    |> validate_number(:amount_cents, greater_than: 0)
    |> assoc_constraint(:account)
  end
end
