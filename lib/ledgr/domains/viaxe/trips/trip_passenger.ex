defmodule Ledgr.Domains.Viaxe.Trips.TripPassenger do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.Viaxe.Trips.Trip
  alias Ledgr.Domains.Viaxe.Customers.Customer

  schema "trip_passengers" do
    belongs_to :trip, Trip
    belongs_to :customer, Customer

    field :is_primary_contact, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(passenger, attrs) do
    passenger
    |> cast(attrs, [:trip_id, :customer_id, :is_primary_contact])
    |> validate_required([:trip_id, :customer_id])
    |> foreign_key_constraint(:trip_id)
    |> foreign_key_constraint(:customer_id)
    |> unique_constraint([:trip_id, :customer_id],
      message: "passenger already added to this trip"
    )
  end
end
