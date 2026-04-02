defmodule Ledgr.Domains.CasaTame.Income.IncomeEntry do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Accounting.Account
  alias Ledgr.Domains.CasaTame.Categories.IncomeCategory

  schema "income_entries" do
    field :date, :date
    field :description, :string
    field :amount_cents, :integer
    field :currency, :string, default: "MXN"
    field :source, :string

    belongs_to :income_category, IncomeCategory
    belongs_to :deposit_account, Account

    timestamps()
  end

  @required_fields ~w(date description amount_cents currency deposit_account_id)a
  @optional_fields ~w(income_category_id source)a

  # USD deposit accounts: 1000-1019. MXN deposit accounts: 1100-1119.
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_inclusion(:currency, ["USD", "MXN"])
    |> assoc_constraint(:deposit_account)
    |> assoc_constraint(:income_category)
    |> validate_currency_matches_account()
  end

  defp validate_currency_matches_account(changeset) do
    currency = Ecto.Changeset.get_field(changeset, :currency)
    account_id = Ecto.Changeset.get_field(changeset, :deposit_account_id)

    if currency && account_id do
      case Ledgr.Repo.get(Account, account_id) do
        nil -> changeset
        account ->
          valid? = case currency do
            "USD" -> account.code >= "1000" and account.code <= "1019"
            "MXN" -> account.code >= "1100" and account.code <= "1119"
            _ -> true
          end

          if valid? do
            changeset
          else
            Ecto.Changeset.add_error(changeset, :deposit_account_id, "must be a #{currency} account")
          end
      end
    else
      changeset
    end
  end
end
