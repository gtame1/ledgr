defmodule Ledgr.Domains.Viaxe.Suppliers.Supplier do
  use Ecto.Schema
  import Ecto.Changeset

  schema "suppliers" do
    field :name, :string
    field :contact_name, :string
    field :email, :string
    field :phone, :string
    field :category, :string
    field :country, :string
    field :city, :string
    field :website, :string
    field :address, :string
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name]
  @optional_fields [
    :contact_name,
    :email,
    :phone,
    :category,
    :country,
    :city,
    :website,
    :address,
    :notes
  ]

  def changeset(supplier, attrs) do
    supplier
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:category, ~w(airline hotel tour_operator transfer insurance other))
  end
end
