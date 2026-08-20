defmodule Ledgr.Domains.Viaxe.Trips do
  @moduledoc """
  Context for managing trips — the umbrella container that groups related bookings
  and tracks which customers are traveling together.
  """

  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Domains.Viaxe.Trips.{Trip, TripPassenger}

  def list_trips(opts \\ []) do
    status = Keyword.get(opts, :status)

    Trip
    |> maybe_filter_status(status)
    |> order_by(desc: :start_date)
    |> preload([:passengers])
    |> Repo.all()
  end

  def get_trip!(id) do
    Trip
    |> preload([:passengers, :trip_passengers, bookings: [:customer, :booking_passengers]])
    |> Repo.get!(id)
  end

  def create_trip(attrs \\ %{}) do
    %Trip{}
    |> Trip.changeset(attrs)
    |> Repo.insert()
  end

  def update_trip(%Trip{} = trip, attrs) do
    trip
    |> Trip.changeset(attrs)
    |> Repo.update()
  end

  def delete_trip(%Trip{} = trip) do
    Repo.delete(trip)
  end

  def change_trip(%Trip{} = trip, attrs \\ %{}) do
    Trip.changeset(trip, attrs)
  end

  # ── Trip Passengers ────────────────────────────────────────────────

  def add_passenger(trip_id, customer_id, opts \\ []) do
    is_primary = Keyword.get(opts, :is_primary_contact, false)

    %TripPassenger{}
    |> TripPassenger.changeset(%{
      trip_id: trip_id,
      customer_id: customer_id,
      is_primary_contact: is_primary
    })
    |> Repo.insert()
  end

  def remove_passenger(trip_id, customer_id) do
    case Repo.get_by(TripPassenger, trip_id: trip_id, customer_id: customer_id) do
      nil -> {:error, :not_found}
      tp -> Repo.delete(tp)
    end
  end

  def trip_select_options do
    Trip
    |> order_by(desc: :start_date)
    |> Repo.all()
    |> Enum.map(fn t -> {t.title, t.id} end)
  end

  # ── Stats ──────────────────────────────────────────────────────────

  def booking_count(%Trip{id: trip_id}) do
    from(b in Ledgr.Domains.Viaxe.Bookings.Booking, where: b.trip_id == ^trip_id)
    |> Repo.aggregate(:count)
  end

  # ── Private ────────────────────────────────────────────────────────

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)
end
