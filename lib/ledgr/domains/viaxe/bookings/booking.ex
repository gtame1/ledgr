defmodule Ledgr.Domains.Viaxe.Bookings.Booking do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.Viaxe.Customers.Customer
  alias Ledgr.Domains.Viaxe.Trips.Trip
  alias Ledgr.Domains.Viaxe.Bookings.{BookingItem, BookingPayment, BookingPassenger}
  alias Ledgr.Core.Partners.Partner

  schema "bookings" do
    belongs_to :customer, Customer
    belongs_to :trip, Trip
    belongs_to :partner, Partner
    has_many :booking_items, BookingItem
    has_many :booking_payments, BookingPayment
    has_many :booking_passengers, BookingPassenger
    has_many :passengers, through: [:booking_passengers, :customer]

    field :status, :string, default: "draft"
    field :booking_date, :date
    field :travel_date, :date
    field :return_date, :date
    field :destination, :string
    # flight, hotel, tour, transfer, car_rental, cruise, insurance, other
    field :booking_type, :string
    # JSONB with type-specific structured fields
    field :booking_details, :map
    # fixed, percentage
    field :commission_type, :string
    # cents if fixed; basis points (×100) if percentage
    field :commission_value, :integer
    field :total_price_cents, :integer, default: 0
    # Commission breakdown (pure agency — no cost/COGS)
    # before partner deduction
    field :gross_commission_cents, :integer, default: 0
    # Archer/Intermex cut
    field :partner_fee_cents, :integer, default: 0
    # basis points stored per-booking
    field :partner_fee_rate, :integer, default: 0
    # Viaxe net = gross - partner_fee
    field :commission_cents, :integer, default: 0
    field :notes, :string

    # Virtual fields
    field :customer_name, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @required_fields [:customer_id, :booking_date, :status]
  @optional_fields [
    :trip_id,
    :partner_id,
    :travel_date,
    :return_date,
    :destination,
    :booking_type,
    :booking_details,
    :commission_type,
    :commission_value,
    :partner_fee_rate,
    :total_price_cents,
    :gross_commission_cents,
    :partner_fee_cents,
    :commission_cents,
    :notes
  ]

  @valid_booking_types ~w(flight hotel tour transfer car_rental cruise insurance other)

  def changeset(booking, attrs) do
    booking
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ~w(draft confirmed in_progress completed canceled))
    |> validate_inclusion(:booking_type, @valid_booking_types)
    |> validate_inclusion(:commission_type, ~w(fixed percentage))
    |> validate_number(:total_price_cents, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:trip_id)
    |> foreign_key_constraint(:partner_id)
    |> calculate_commission()
  end

  @doc "Recalculates totals from booking items; preserves commission type/value and partner_fee_rate"
  def recalculate_totals(booking, items) do
    total_price =
      Enum.reduce(items, 0, fn item, acc -> acc + item.price_cents * item.quantity end)

    booking
    |> Ecto.Changeset.change(%{total_price_cents: total_price})
    |> calculate_commission()
  end

  # Calculates gross commission and splits into partner_fee + net commission_cents.
  defp calculate_commission(changeset) do
    commission_type = get_field(changeset, :commission_type)
    commission_value = get_field(changeset, :commission_value)
    total_price = get_field(changeset, :total_price_cents) || 0
    partner_fee_rate = get_field(changeset, :partner_fee_rate) || 0

    gross =
      cond do
        commission_type == "fixed" && commission_value ->
          commission_value

        commission_type == "percentage" && commission_value && total_price > 0 ->
          div(total_price * commission_value, 10_000)

        true ->
          0
      end

    partner_fee =
      if gross > 0 && partner_fee_rate > 0, do: div(gross * partner_fee_rate, 10_000), else: 0

    changeset
    |> put_change(:gross_commission_cents, gross)
    |> put_change(:partner_fee_cents, partner_fee)
    |> put_change(:commission_cents, max(gross - partner_fee, 0))
  end
end
