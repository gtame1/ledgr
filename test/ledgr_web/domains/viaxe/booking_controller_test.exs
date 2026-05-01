defmodule LedgrWeb.Domains.Viaxe.BookingControllerTest do
  use LedgrWeb.ConnCase

  alias Ledgr.Domains.Viaxe.Bookings
  alias Ledgr.Domains.Viaxe.Customers
  alias Ledgr.Domains.Viaxe.Trips

  setup %{conn: conn} do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)

    {:ok, user} =
      Ledgr.Core.Accounts.create_user(%{email: "viaxe@test.example", password: "password123!"})

    conn = Phoenix.ConnTest.init_test_session(conn, %{"user_id:viaxe" => user.id})

    {:ok, customer} =
      Customers.create_customer(%{
        first_name: "Ana",
        last_name: "García",
        phone: "+525512345678"
      })

    {:ok, trip} =
      Trips.create_trip(%{
        title: "Cancún Escape",
        start_date: ~D[2026-07-01],
        end_date: ~D[2026-07-10],
        status: "planning"
      })

    {:ok, booking} =
      Bookings.create_booking(%{
        customer_id: customer.id,
        trip_id: trip.id,
        booking_date: ~D[2026-03-01],
        status: "draft",
        booking_type: "flight",
        destination: "CUN",
        total_price_cents: 350_000
      })

    {:ok, conn: conn, customer: customer, trip: trip, booking: booking}
  end

  describe "index/2" do
    test "lists all bookings", %{conn: conn} do
      conn = get(conn, "/app/viaxe/bookings")
      assert html_response(conn, 200)
    end

    test "filters bookings by status", %{conn: conn} do
      conn = get(conn, "/app/viaxe/bookings?status=draft")
      assert html_response(conn, 200)
    end
  end

  describe "show/2" do
    test "shows booking with payment summary", %{conn: conn, booking: booking} do
      conn = get(conn, "/app/viaxe/bookings/#{booking.id}")
      assert html_response(conn, 200) =~ "CUN"
    end
  end

  describe "new/2" do
    test "renders new booking form", %{conn: conn} do
      conn = get(conn, "/app/viaxe/bookings/new")
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "create/2" do
    test "creates booking and redirects on valid params", %{conn: conn, customer: customer} do
      params = %{
        "booking" => %{
          "customer_id" => customer.id,
          "booking_date" => "2026-04-01",
          "status" => "draft",
          "booking_type" => "hotel",
          "destination" => "CUN"
        }
      }

      conn = post(conn, "/app/viaxe/bookings", params)
      assert redirected_to(conn) =~ "/app/viaxe/bookings/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "created"
    end

    test "renders errors on invalid params (missing required fields)", %{conn: conn} do
      params = %{
        "booking" => %{
          "customer_id" => "",
          "booking_date" => "",
          "status" => ""
        }
      }

      conn = post(conn, "/app/viaxe/bookings", params)
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "edit/2" do
    test "renders edit form", %{conn: conn, booking: booking} do
      conn = get(conn, "/app/viaxe/bookings/#{booking.id}/edit")
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "update/2" do
    test "updates booking and redirects on valid params", %{
      conn: conn,
      booking: booking,
      customer: customer
    } do
      params = %{
        "booking" => %{
          "customer_id" => customer.id,
          "booking_date" => "2026-03-01",
          "status" => "draft",
          "booking_type" => "flight",
          "destination" => "MEX"
        }
      }

      conn = put(conn, "/app/viaxe/bookings/#{booking.id}", params)
      assert redirected_to(conn) == "/app/viaxe/bookings/#{booking.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "updated"
    end

    test "renders errors on invalid params", %{conn: conn, booking: booking} do
      params = %{
        "booking" => %{
          "customer_id" => "",
          "booking_date" => "",
          "status" => ""
        }
      }

      conn = put(conn, "/app/viaxe/bookings/#{booking.id}", params)
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "update_status/2" do
    test "updates booking status and redirects", %{conn: conn, booking: booking} do
      params = %{"status" => %{"status" => "confirmed"}}
      conn = post(conn, "/app/viaxe/bookings/#{booking.id}/status", params)
      assert redirected_to(conn) == "/app/viaxe/bookings/#{booking.id}"
    end
  end

  describe "delete/2" do
    test "deletes booking and redirects", %{conn: conn, booking: booking} do
      conn = delete(conn, "/app/viaxe/bookings/#{booking.id}")
      assert redirected_to(conn) == "/app/viaxe/bookings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "deleted"
    end
  end
end
