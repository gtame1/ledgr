defmodule Ledgr.Domains.Viaxe.Services.Service do
  use Ecto.Schema
  import Ecto.Changeset

  schema "services" do
    field :name, :string
    field :category, :string
    field :description, :string
    field :default_cost_cents, :integer
    field :default_price_cents, :integer
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :category]
  @optional_fields [:description, :default_cost_cents, :default_price_cents, :active]

  def changeset(service, attrs) do
    service
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:category, ~w(flight hotel tour transfer insurance package))
    |> validate_number(:default_cost_cents, greater_than_or_equal_to: 0)
    |> validate_number(:default_price_cents, greater_than_or_equal_to: 0)
  end
end
