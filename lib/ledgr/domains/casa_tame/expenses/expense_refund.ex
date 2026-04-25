defmodule Ledgr.Domains.CasaTame.Expenses.ExpenseRefund do
  @moduledoc """
  Records a partial or full refund for a Casa Tame personal expense.

  Each refund posts its own journal entry:
    DR refund_to_account_id   (money comes back into an asset/liability account)
    CR expense_account_id     (reduces net spend in that category)

  Multiple refunds on the same expense are allowed; the sum may not exceed the
  original expense amount_cents.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Accounting.Account

  schema "expense_refunds" do
    field :date,         :date
    field :amount_cents, :integer
    field :currency,     :string
    field :reason,       :string

    belongs_to :expense, Ledgr.Domains.CasaTame.Expenses.CasaTameExpense
    belongs_to :refund_to_account, Account

    timestamps()
  end

  @required_fields ~w(date amount_cents currency expense_id refund_to_account_id)a
  @optional_fields ~w(reason)a

  # Mirror the same code ranges used in CasaTameExpense
  @usd_ranges [{"1000", "1099"}, {"2000", "2099"}]
  @mxn_ranges [{"1100", "1199"}, {"2100", "2199"}]

  def changeset(refund, attrs) do
    refund
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_inclusion(:currency, ["USD", "MXN"])
    |> assoc_constraint(:expense)
    |> assoc_constraint(:refund_to_account)
    |> validate_currency_matches_account()
  end

  defp validate_currency_matches_account(changeset) do
    currency   = get_field(changeset, :currency)
    account_id = get_field(changeset, :refund_to_account_id)

    if currency && account_id do
      case Ledgr.Repo.get(Account, account_id) do
        nil -> changeset
        account ->
          valid? =
            case currency do
              "USD" -> Enum.any?(@usd_ranges, fn {from, to} -> account.code >= from and account.code <= to end)
              "MXN" -> Enum.any?(@mxn_ranges, fn {from, to} -> account.code >= from and account.code <= to end)
              _ -> true
            end

          if valid?,
            do: changeset,
            else: add_error(changeset, :refund_to_account_id, "must be a #{currency} account")
      end
    else
      changeset
    end
  end
end
