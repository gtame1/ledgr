defmodule LedgrWeb.Domains.Viaxe.BookingController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.Viaxe.Bookings
  alias Ledgr.Domains.Viaxe.Bookings.Booking
  alias Ledgr.Domains.Viaxe.Customers
  alias Ledgr.Domains.Viaxe.Trips
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, params) do
    status = params["status"]
    bookings = Bookings.list_bookings(status: status)
    status_counts = Bookings.count_by_status()

    render(conn, :index,
      bookings: bookings,
      status_counts: status_counts,
      current_status: status
    )
  end

  def new(conn, _params) do
    changeset = Bookings.change_booking(%Booking{booking_date: today_mx()})
    customers = Customers.customer_select_options()
    trips = Trips.trip_select_options()

    render(conn, :new,
      changeset: changeset,
      customers: customers,
      trips: trips,
      action: dp(conn, "/bookings")
    )
  end

  def create(conn, %{"booking" => booking_params}) do
    booking_params =
      MoneyHelper.convert_params_pesos_to_cents(booking_params, [:total_price_cents])

    case Bookings.create_booking(booking_params) do
      {:ok, booking} ->
        conn
        |> put_flash(:info, "Booking created successfully.")
        |> redirect(to: dp(conn, "/bookings/#{booking.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = Customers.customer_select_options()
        trips = Trips.trip_select_options()

        render(conn, :new,
          changeset: changeset,
          customers: customers,
          trips: trips,
          action: dp(conn, "/bookings")
        )
    end
  end

  def show(conn, %{"id" => id}) do
    booking = Bookings.get_booking!(id)
    payment_summary = Bookings.payment_summary(booking)

    render(conn, :show,
      booking: booking,
      payment_summary: payment_summary
    )
  end

  def edit(conn, %{"id" => id}) do
    booking = Bookings.get_booking!(id)
    changeset = Bookings.change_booking(booking)
    customers = Customers.customer_select_options()
    trips = Trips.trip_select_options()

    render(conn, :edit,
      booking: booking,
      changeset: changeset,
      customers: customers,
      trips: trips,
      action: dp(conn, "/bookings/#{id}")
    )
  end

  def update(conn, %{"id" => id, "booking" => booking_params}) do
    booking = Bookings.get_booking!(id)

    case Bookings.update_booking(booking, booking_params) do
      {:ok, _booking} ->
        conn
        |> put_flash(:info, "Booking updated successfully.")
        |> redirect(to: dp(conn, "/bookings/#{id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = Customers.customer_select_options()
        trips = Trips.trip_select_options()

        render(conn, :edit,
          booking: booking,
          changeset: changeset,
          customers: customers,
          trips: trips,
          action: dp(conn, "/bookings/#{id}")
        )
    end
  end

  def update_status(conn, %{"id" => id, "status" => %{"status" => new_status}}) do
    booking = Bookings.get_booking!(id)

    case Bookings.update_booking_status(booking, new_status) do
      {:ok, _booking} ->
        conn
        |> put_flash(:info, "Booking status updated to #{String.capitalize(new_status)}.")
        |> redirect(to: dp(conn, "/bookings/#{id}"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not update booking status.")
        |> redirect(to: dp(conn, "/bookings/#{id}"))
    end
  end

  def delete(conn, %{"id" => id}) do
    booking = Bookings.get_booking!(id)
    {:ok, _} = Bookings.delete_booking(booking)

    conn
    |> put_flash(:info, "Booking deleted successfully.")
    |> redirect(to: dp(conn, "/bookings"))
  end
end

defmodule LedgrWeb.Domains.Viaxe.BookingHTML do
  use LedgrWeb, :html

  embed_templates "booking_html/*"

  def status_class("draft"), do: ""
  def status_class("confirmed"), do: "status-paid"
  def status_class("in_progress"), do: "status-partial"
  def status_class("completed"), do: "status-paid"
  def status_class("canceled"), do: "status-unpaid"
  def status_class(_), do: ""

  def booking_type_label("flight"), do: "✈️ Flight"
  def booking_type_label("hotel"), do: "🏨 Hotel"
  def booking_type_label("tour"), do: "🗺 Tour"
  def booking_type_label("transfer"), do: "🚌 Transfer"
  def booking_type_label("car_rental"), do: "🚗 Car Rental"
  def booking_type_label("cruise"), do: "🚢 Cruise"
  def booking_type_label("insurance"), do: "🛡 Insurance"
  def booking_type_label("other"), do: "📋 Other"
  def booking_type_label(nil), do: "—"
  def booking_type_label(t), do: String.capitalize(t)
end
