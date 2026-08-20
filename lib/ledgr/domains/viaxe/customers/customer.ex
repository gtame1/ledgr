defmodule Ledgr.Domains.Viaxe.Customers.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.Viaxe.Customers.CustomerTravelProfile
  alias Ledgr.Domains.Viaxe.TravelDocuments.{Passport, Visa, LoyaltyProgram}

  schema "customers" do
    field :first_name, :string
    field :middle_name, :string
    field :last_name, :string
    field :maternal_last_name, :string
    field :email, :string
    field :phone, :string

    has_one :travel_profile, CustomerTravelProfile
    has_many :passports, Passport
    has_many :visas, Visa
    has_many :loyalty_programs, LoyaltyProgram

    timestamps(type: :utc_datetime)
  end

  @required_fields [:first_name, :last_name, :phone]
  @optional_fields [:middle_name, :maternal_last_name, :email]

  def changeset(customer, attrs) do
    customer
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:phone, message: "a customer with this phone number already exists")
    |> validate_email_format()
  end

  @doc "Returns display name: first + last (middle and maternal are optional)"
  def full_name(%__MODULE__{} = customer) do
    [customer.first_name, customer.middle_name, customer.last_name, customer.maternal_last_name]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
  end

  defp validate_email_format(changeset) do
    email = get_field(changeset, :email)

    if email && email != "" do
      validate_format(changeset, :email, ~r/^[^\s]+@[^\s]+$/,
        message: "must be a valid email address"
      )
    else
      changeset
    end
  end
end
