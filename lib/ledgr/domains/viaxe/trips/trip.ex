defmodule Ledgr.Domains.Viaxe.Trips.Trip do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.Viaxe.Trips.TripPassenger
  alias Ledgr.Domains.Viaxe.Bookings.Booking

  schema "trips" do
    field :title, :string
    field :description, :string
    field :start_date, :date
    field :end_date, :date
    field :status, :string, default: "planning"
    field :notes, :string

    has_many :trip_passengers, TripPassenger
    has_many :passengers, through: [:trip_passengers, :customer]
    has_many :bookings, Booking

    timestamps(type: :utc_datetime)
  end

  @required_fields [:title]
  @optional_fields [:description, :start_date, :end_date, :status, :notes]

  @valid_statuses ~w(planning confirmed active completed cancelled)

  def changeset(trip, attrs) do
    trip
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses,
      message: "must be one of: #{Enum.join(@valid_statuses, ", ")}"
    )
    |> validate_date_order()
  end

  defp validate_date_order(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date && Date.compare(end_date, start_date) == :lt do
      add_error(changeset, :end_date, "must be on or after the start date")
    else
      changeset
    end
  end
end
