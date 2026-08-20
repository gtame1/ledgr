defmodule LedgrWeb.Domains.Viaxe.TripControllerTest do
  use LedgrWeb.ConnCase

  alias Ledgr.Domains.Viaxe.{Trips, Customers, Bookings}

  setup %{conn: conn} do
    # Switch to Viaxe repo for all test data — DomainPlug will also set this
    # when requests hit /app/viaxe/... routes.
    Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)

    # Create a user in the Viaxe database for authentication
    {:ok, user} =
      Ledgr.Core.Accounts.create_user(%{email: "viaxe@test.example", password: "password123!"})

    conn = Phoenix.ConnTest.init_test_session(conn, %{"user_id:viaxe" => user.id})

    {:ok, trip} =
      Trips.create_trip(%{
        title: "Paris Getaway",
        start_date: ~D[2026-03-01],
        end_date: ~D[2026-03-15],
        status: "planning"
      })

    {:ok, customer} =
      Customers.create_customer(%{
        first_name: "Ana",
        last_name: "García",
        phone: "+525512345678"
      })

    {:ok, conn: conn, trip: trip, customer: customer}
  end

  # ── index/2 ───────────────────────────────────────────────────────────────

  describe "index/2" do
    test "renders the trips list", %{conn: conn, trip: trip} do
      conn = get(conn, "/app/viaxe/trips")
      assert html_response(conn, 200) =~ trip.title
    end

    test "filters trips by status param", %{conn: conn} do
      {:ok, _} = Trips.create_trip(%{title: "Confirmed Trip", status: "confirmed"})

      conn = get(conn, "/app/viaxe/trips?status=confirmed")
      html = html_response(conn, 200)

      assert html =~ "Confirmed Trip"
      refute html =~ "Paris Getaway"
    end
  end

  # ── show/2 ────────────────────────────────────────────────────────────────

  describe "show/2" do
    test "renders trip details page", %{conn: conn, trip: trip} do
      conn = get(conn, "/app/viaxe/trips/#{trip.id}")
      assert html_response(conn, 200) =~ trip.title
    end
  end

  # ── calendar/2 ────────────────────────────────────────────────────────────

  describe "calendar/2" do
    test "renders calendar page with correct month headers", %{conn: conn, trip: trip} do
      conn = get(conn, "/app/viaxe/trips/#{trip.id}/calendar")
      html = html_response(conn, 200)

      assert html =~ trip.title
      assert html =~ "March 2026"
    end

    test "shows booking events for their travel_date", %{
      conn: conn,
      trip: trip,
      customer: customer
    } do
      {:ok, _booking} =
        Bookings.create_booking(%{
          customer_id: customer.id,
          trip_id: trip.id,
          booking_date: ~D[2026-02-01],
          status: "confirmed",
          booking_type: "flight",
          travel_date: ~D[2026-03-05],
          destination: "Paris"
        })

      conn = get(conn, "/app/viaxe/trips/#{trip.id}/calendar")
      html = html_response(conn, 200)

      assert html =~ "✈️"
      assert html =~ "Paris"
    end

    test "expands calendar to cover booking months outside the trip date range", %{
      conn: conn,
      trip: trip,
      customer: customer
    } do
      {:ok, _booking} =
        Bookings.create_booking(%{
          customer_id: customer.id,
          trip_id: trip.id,
          booking_date: ~D[2026-02-01],
          status: "confirmed",
          booking_type: "hotel",
          travel_date: ~D[2026-04-01],
          destination: "Lyon"
        })

      conn = get(conn, "/app/viaxe/trips/#{trip.id}/calendar")
      html = html_response(conn, 200)

      assert html =~ "March 2026"
      assert html =~ "April 2026"
    end

    test "renders correctly for a trip with no bookings", %{conn: conn, trip: trip} do
      conn = get(conn, "/app/viaxe/trips/#{trip.id}/calendar")
      assert html_response(conn, 200) =~ "March 2026"
    end
  end

  # ── create/2 ──────────────────────────────────────────────────────────────

  describe "create/2" do
    test "creates a trip and redirects to show", %{conn: conn} do
      conn = post(conn, "/app/viaxe/trips", trip: %{title: "Rome Adventure", status: "planning"})

      assert redirected_to(conn) =~ "/app/viaxe/trips/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Trip created successfully."
    end

    test "re-renders form with validation errors when title is blank", %{conn: conn} do
      conn = post(conn, "/app/viaxe/trips", trip: %{title: ""})
      assert html_response(conn, 200) =~ "can&#39;t be blank"
    end
  end

  # ── delete/2 ──────────────────────────────────────────────────────────────

  describe "delete/2" do
    test "deletes trip and redirects to index", %{conn: conn, trip: trip} do
      conn = delete(conn, "/app/viaxe/trips/#{trip.id}")

      assert redirected_to(conn) == "/app/viaxe/trips"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Trip deleted successfully."
    end
  end
end
