defmodule Ledgr.Domains.CasaTame.Expenses.CasaTameExpense do
  @moduledoc """
  Extended expense schema for Casa Tame with currency and hierarchical category support.
  Maps to the same `expenses` table but includes the domain-specific columns.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Accounting.Account
  alias Ledgr.Domains.CasaTame.Categories.ExpenseCategory

  schema "expenses" do
    field :date, :date
    field :description, :string
    field :amount_cents, :integer
    field :category, :string
    field :iva_cents, :integer, default: 0
    field :payee, :string
    field :currency, :string, default: "MXN"

    belongs_to :expense_account, Account
    belongs_to :paid_from_account, Account
    belongs_to :expense_category, ExpenseCategory

    timestamps()
  end

  @required_fields ~w(date description amount_cents expense_account_id paid_from_account_id currency)a
  @optional_fields ~w(category iva_cents payee expense_category_id)a

  # USD accounts: 1000-1099, 2000-2099. MXN accounts: 1100-1199, 2100-2199.
  @usd_ranges [{"1000", "1099"}, {"2000", "2099"}]
  @mxn_ranges [{"1100", "1199"}, {"2100", "2199"}]

  def changeset(expense, attrs) do
    expense
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_number(:iva_cents, greater_than_or_equal_to: 0)
    |> validate_inclusion(:currency, ["USD", "MXN"])
    |> assoc_constraint(:expense_account)
    |> assoc_constraint(:paid_from_account)
    |> assoc_constraint(:expense_category)
    |> validate_currency_matches_account()
  end

  defp validate_currency_matches_account(changeset) do
    currency = get_field(changeset, :currency)
    account_id = get_field(changeset, :paid_from_account_id)

    if currency && account_id do
      case Ledgr.Repo.get(Account, account_id) do
        nil -> changeset
        account ->
          valid? = case currency do
            "USD" -> Enum.any?(@usd_ranges, fn {from, to} -> account.code >= from and account.code <= to end)
            "MXN" -> Enum.any?(@mxn_ranges, fn {from, to} -> account.code >= from and account.code <= to end)
            _ -> true
          end

          if valid? do
            changeset
          else
            add_error(changeset, :paid_from_account_id, "must be a #{currency} account")
          end
      end
    else
      changeset
    end
  end
end
