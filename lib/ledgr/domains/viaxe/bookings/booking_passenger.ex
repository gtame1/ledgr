defmodule Ledgr.Domains.Viaxe.Bookings.BookingPassenger do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.Viaxe.Bookings.Booking
  alias Ledgr.Domains.Viaxe.Customers.Customer

  schema "booking_passengers" do
    belongs_to :booking, Booking
    belongs_to :customer, Customer

    timestamps(type: :utc_datetime)
  end

  def changeset(passenger, attrs) do
    passenger
    |> cast(attrs, [:booking_id, :customer_id])
    |> validate_required([:booking_id, :customer_id])
    |> foreign_key_constraint(:booking_id)
    |> foreign_key_constraint(:customer_id)
    |> unique_constraint([:booking_id, :customer_id],
      message: "passenger already added to this booking"
    )
  end
end
