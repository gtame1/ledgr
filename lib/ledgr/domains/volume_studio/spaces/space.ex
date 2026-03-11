defmodule Ledgr.Domains.VolumeStudio.Spaces.Space do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.VolumeStudio.Spaces.SpaceRental

  schema "spaces" do
    has_many :space_rentals, SpaceRental

    field :name, :string
    field :description, :string
    field :capacity, :integer
    field :hourly_rate_cents, :integer
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name]
  @optional_fields [:description, :capacity, :hourly_rate_cents, :active]

  def changeset(space, attrs) do
    space
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:capacity, greater_than: 0)
    |> validate_number(:hourly_rate_cents, greater_than_or_equal_to: 0)
  end
end
