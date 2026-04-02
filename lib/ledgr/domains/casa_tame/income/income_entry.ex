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

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_inclusion(:currency, ["USD", "MXN"])
    |> assoc_constraint(:deposit_account)
    |> assoc_constraint(:income_category)
  end
end
