defmodule Ledgr.Domains.Viaxe.Bookings.BookingItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.Viaxe.Bookings.Booking
  alias Ledgr.Domains.Viaxe.Services.Service
  alias Ledgr.Domains.Viaxe.Suppliers.Supplier

  schema "booking_items" do
    belongs_to :booking, Booking
    belongs_to :service, Service
    belongs_to :supplier, Supplier

    field :description, :string
    field :cost_cents, :integer
    field :price_cents, :integer
    field :quantity, :integer, default: 1

    timestamps(type: :utc_datetime)
  end

  @required_fields [:booking_id, :description, :cost_cents, :price_cents]
  @optional_fields [:service_id, :supplier_id, :quantity]

  def changeset(booking_item, attrs) do
    booking_item
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:cost_cents, greater_than_or_equal_to: 0)
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:booking_id)
  end
end
