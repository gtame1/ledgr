defmodule Ledgr.Repos.Viaxe.Migrations.CreateTripsAndUpdateBookings do
  use Ecto.Migration

  def change do
    # ── Trips (umbrella container for related bookings) ──────
    create table(:trips) do
      add :title, :string, null: false
      add :description, :text
      add :start_date, :date
      add :end_date, :date
      add :status, :string, null: false, default: "planning"
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:trips, [:status])
    create index(:trips, [:start_date])

    create constraint(:trips, :valid_trip_status,
      check: "status IN ('planning','confirmed','active','completed','cancelled')"
    )

    # ── Trip Passengers (which customers are on a trip) ──────
    create table(:trip_passengers) do
      add :trip_id, references(:trips, on_delete: :delete_all), null: false
      add :customer_id, references(:customers, on_delete: :restrict), null: false
      add :is_primary_contact, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:trip_passengers, [:trip_id, :customer_id])
    create index(:trip_passengers, [:customer_id])

    # ── Alter Bookings ───────────────────────────────────────
    alter table(:bookings) do
      add :trip_id, references(:trips, on_delete: :restrict)   # nullable — standalone ok
      add :booking_type, :string                                # flight, hotel, tour, transfer, car_rental, cruise, insurance, other
      add :booking_details, :map                                # JSONB for type-specific fields
      add :commission_type, :string                             # fixed, percentage
      add :commission_value, :integer                           # cents if fixed; basis points (×100) if percentage
      remove :passengers, :integer, default: 1                  # replaced by booking_passengers count
    end

    create index(:bookings, [:trip_id])
    create index(:bookings, [:booking_type])

    # ── Booking Passengers (subset of travelers per booking) ─
    create table(:booking_passengers) do
      add :booking_id, references(:bookings, on_delete: :delete_all), null: false
      add :customer_id, references(:customers, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:booking_passengers, [:booking_id, :customer_id])
    create index(:booking_passengers, [:customer_id])
  end
end
