defmodule Ledgr.Domains.Viaxe.TravelDocuments.Visa do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.Viaxe.Customers.Customer

  schema "customer_visas" do
    belongs_to :customer, Customer

    # destination country code
    field :country, :string
    # tourist, work, student, transit, multiple_entry
    field :visa_type, :string
    field :visa_number, :string
    field :issue_date, :date
    field :expiry_date, :date
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:customer_id, :country]
  @optional_fields [:visa_type, :visa_number, :issue_date, :expiry_date, :notes]

  def changeset(visa, attrs) do
    visa
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:visa_type, ~w(tourist work student transit multiple_entry))
    |> foreign_key_constraint(:customer_id)
  end
end
