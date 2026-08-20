defmodule LedgrWeb.Domains.Viaxe.TripController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.Viaxe.Trips
  alias Ledgr.Domains.Viaxe.Trips.Trip
  alias Ledgr.Domains.Viaxe.Customers
  alias LedgrWeb.Domains.Viaxe.TripHTML

  def index(conn, params) do
    status = params["status"]
    trips = Trips.list_trips(status: status)
    render(conn, :index, trips: trips, current_status: status)
  end

  def show(conn, %{"id" => id}) do
    trip = Trips.get_trip!(id)
    render(conn, :show, trip: trip)
  end

  def calendar(conn, %{"id" => id}) do
    trip = Trips.get_trip!(id)
    calendar_months = TripHTML.calendar_months(trip)
    events_by_date = TripHTML.calendar_events(trip.bookings)

    render(conn, :calendar,
      trip: trip,
      calendar_months: calendar_months,
      events_by_date: events_by_date
    )
  end

  def new(conn, _params) do
    changeset = Trips.change_trip(%Trip{})
    customers = Customers.customer_select_options()

    render(conn, :new,
      changeset: changeset,
      customers: customers,
      action: dp(conn, "/trips")
    )
  end

  def create(conn, %{"trip" => trip_params}) do
    {passenger_ids, trip_params} = Map.pop(trip_params, "passenger_ids", [])

    case Trips.create_trip(trip_params) do
      {:ok, trip} ->
        passenger_ids
        |> List.wrap()
        |> Enum.reject(&(&1 == "" or is_nil(&1)))
        |> Enum.each(&Trips.add_passenger(trip.id, &1))

        conn
        |> put_flash(:info, "Trip created successfully.")
        |> redirect(to: dp(conn, "/trips/#{trip.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = Customers.customer_select_options()

        render(conn, :new,
          changeset: changeset,
          customers: customers,
          action: dp(conn, "/trips")
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    trip = Trips.get_trip!(id)
    changeset = Trips.change_trip(trip)
    customers = Customers.customer_select_options()
    current_passenger_ids = Enum.map(trip.passengers, & &1.id)

    render(conn, :edit,
      trip: trip,
      changeset: changeset,
      customers: customers,
      current_passenger_ids: current_passenger_ids,
      action: dp(conn, "/trips/#{id}")
    )
  end

  def update(conn, %{"id" => id, "trip" => trip_params}) do
    trip = Trips.get_trip!(id)
    {new_passenger_ids, trip_params} = Map.pop(trip_params, "passenger_ids", [])

    case Trips.update_trip(trip, trip_params) do
      {:ok, trip} ->
        new_passenger_ids =
          new_passenger_ids
          |> List.wrap()
          |> Enum.reject(&(&1 == "" or is_nil(&1)))
          |> Enum.map(&String.to_integer(to_string(&1)))

        current_ids = Enum.map(trip.passengers, & &1.id)

        (current_ids -- new_passenger_ids)
        |> Enum.each(&Trips.remove_passenger(trip.id, &1))

        (new_passenger_ids -- current_ids)
        |> Enum.each(&Trips.add_passenger(trip.id, &1))

        conn
        |> put_flash(:info, "Trip updated successfully.")
        |> redirect(to: dp(conn, "/trips/#{trip.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = Customers.customer_select_options()
        current_passenger_ids = Enum.map(trip.passengers, & &1.id)

        render(conn, :edit,
          trip: trip,
          changeset: changeset,
          customers: customers,
          current_passenger_ids: current_passenger_ids,
          action: dp(conn, "/trips/#{id}")
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    trip = Trips.get_trip!(id)
    {:ok, _} = Trips.delete_trip(trip)

    conn
    |> put_flash(:info, "Trip deleted successfully.")
    |> redirect(to: dp(conn, "/trips"))
  end
end

defmodule LedgrWeb.Domains.Viaxe.TripHTML do
  use LedgrWeb, :html

  embed_templates "trip_html/*"

  def status_class("planning"), do: ""
  def status_class("confirmed"), do: "status-paid"
  def status_class("active"), do: "status-partial"
  def status_class("completed"), do: "status-paid"
  def status_class("cancelled"), do: "status-unpaid"
  def status_class(_), do: ""

  # ── Calendar helpers ──────────────────────────────────────────────────────

  @doc "Returns [{year, month}] covering the trip's date range, derived from
        trip start/end dates and booking travel/return dates."
  def calendar_months(trip) do
    booking_dates =
      trip.bookings
      |> Enum.flat_map(&[&1.travel_date, &1.return_date])

    dates =
      [trip.start_date, trip.end_date | booking_dates]
      |> Enum.reject(&is_nil/1)
      |> Enum.sort({:asc, Date})

    case dates do
      [] ->
        today = today_mx()
        [{today.year, today.month}]

      _ ->
        first = %{List.first(dates) | day: 1}
        last = %{List.last(dates) | day: 1}
        months_between(first, last)
    end
  end

  @doc "Groups bookings by travel_date. Bookings without a travel_date are omitted."
  def calendar_events(bookings) do
    bookings
    |> Enum.reject(&is_nil(&1.travel_date))
    |> Enum.group_by(& &1.travel_date)
  end

  @doc "Number of blank Mon-first leading cells before the 1st of the month."
  def calendar_leading_blanks(year, month) do
    # Date.day_of_week: Mon=1 … Sun=7; Mon-first grid needs Mon=0 blanks.
    Date.new!(year, month, 1) |> Date.day_of_week() |> Kernel.-(1)
  end

  @doc "Number of days in the given year/month."
  def calendar_days_in_month(year, month) do
    next_first =
      case month do
        12 -> Date.new!(year + 1, 1, 1)
        m -> Date.new!(year, m + 1, 1)
      end

    Date.add(next_first, -1).day
  end

  @doc "Human-readable month + year label, e.g. \"March 2026\"."
  def month_label(month, year) do
    month_name =
      ~w(January February March April May June
         July August September October November December)
      |> Enum.at(month - 1)

    "#{month_name} #{year}"
  end

  @doc "Small emoji icon for a booking type."
  def event_icon("flight"), do: "✈️"
  def event_icon("hotel"), do: "🏨"
  def event_icon("tour"), do: "🗺"
  def event_icon("transfer"), do: "🚌"
  def event_icon("car_rental"), do: "🚗"
  def event_icon("cruise"), do: "🚢"
  def event_icon("insurance"), do: "🛡"
  def event_icon(_), do: "📋"

  # ── Private ───────────────────────────────────────────────────────────────

  defp months_between(first, last) do
    Stream.unfold(first, fn d ->
      if Date.compare(d, last) == :gt do
        nil
      else
        next =
          case d.month do
            12 -> %{d | year: d.year + 1, month: 1}
            m -> %{d | month: m + 1}
          end

        {{d.year, d.month}, next}
      end
    end)
    |> Enum.to_list()
  end
end
