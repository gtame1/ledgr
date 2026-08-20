defmodule Ledgr.Domains.Viaxe.TravelDocuments.Passport do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.Viaxe.Customers.Customer

  schema "passports" do
    belongs_to :customer, Customer

    # issuing country code e.g. "MX", "US"
    field :country, :string
    field :number, :string
    field :issue_date, :date
    field :expiry_date, :date
    field :is_primary, :boolean, default: false
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:customer_id, :country, :number]
  @optional_fields [:issue_date, :expiry_date, :is_primary, :notes]

  def changeset(passport, attrs) do
    passport
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:customer_id)
  end
end
