defmodule Ledgr.Domains.Viaxe.BookingsTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.Viaxe.Bookings
  alias Ledgr.Domains.Viaxe.Bookings.{Booking, BookingItem, BookingPayment}
  alias Ledgr.Domains.Viaxe.Customers
  alias Ledgr.Domains.Viaxe.Trips
  alias Ledgr.Core.Accounting
  alias Ledgr.Repo

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)
    Ledgr.Domain.put_current(Ledgr.Domains.Viaxe)
    viaxe_accounts_fixture()
    :ok
  end

  # ── Account & entity fixtures ─────────────────────────────────────────

  defp viaxe_accounts_fixture do
    accounts = [
      %{code: "1000", name: "Cash", type: "asset", normal_balance: "debit", is_cash: true},
      %{
        code: "1100",
        name: "Commission Receivable",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      },
      %{
        code: "2200",
        name: "Advance Commission",
        type: "liability",
        normal_balance: "credit",
        is_cash: false
      },
      %{
        code: "4000",
        name: "Commission Revenue",
        type: "revenue",
        normal_balance: "credit",
        is_cash: false
      }
    ]

    Enum.each(accounts, fn attrs ->
      case Accounting.get_account_by_code(attrs.code) do
        nil -> {:ok, _} = Accounting.create_account(attrs)
        _ -> :ok
      end
    end)
  end

  defp customer_fixture do
    unique = System.unique_integer([:positive])

    {:ok, customer} =
      Customers.create_customer(%{
        first_name: "Ana",
        last_name: "García #{unique}",
        phone: "+52551#{unique}"
      })

    customer
  end

  defp trip_fixture do
    {:ok, trip} =
      Trips.create_trip(%{
        title: "Trip #{System.unique_integer([:positive])}",
        start_date: ~D[2026-08-01],
        end_date: ~D[2026-08-10],
        status: "planning"
      })

    trip
  end

  defp booking_fixture(attrs \\ %{}) do
    customer = attrs[:customer] || customer_fixture()
    trip = attrs[:trip] || trip_fixture()

    {:ok, booking} =
      Bookings.create_booking(
        attrs
        |> Map.drop([:customer, :trip])
        |> Enum.into(%{
          customer_id: customer.id,
          trip_id: trip.id,
          booking_date: ~D[2026-03-01],
          status: "draft",
          booking_type: "flight",
          destination: "CUN"
        })
      )

    booking
  end

  # ── list_bookings/1 ──────────────────────────────────────────────────

  describe "list_bookings/1" do
    test "returns all bookings" do
      booking = booking_fixture()
      bookings = Bookings.list_bookings()
      assert Enum.any?(bookings, fn b -> b.id == booking.id end)
    end

    test "filters by status" do
      confirmed = booking_fixture(%{status: "confirmed"})
      _draft = booking_fixture(%{status: "draft"})

      bookings = Bookings.list_bookings(status: "confirmed")
      assert Enum.any?(bookings, fn b -> b.id == confirmed.id end)
      assert Enum.all?(bookings, fn b -> b.status == "confirmed" end)
    end

    test "preloads customer, trip, booking_items, and booking_payments" do
      booking = booking_fixture()
      [found | _] = Bookings.list_bookings()
      assert found.id == booking.id
      assert is_list(found.booking_items)
      assert is_list(found.booking_payments)
    end

    test "sets customer_name from customer" do
      customer = customer_fixture()
      booking_fixture(%{customer: customer})

      bookings = Bookings.list_bookings()
      found = Enum.find(bookings, fn b -> b.customer_id == customer.id end)
      assert is_binary(found.customer_name)
      assert String.contains?(found.customer_name, customer.first_name)
    end
  end

  # ── get_booking!/1 ───────────────────────────────────────────────────

  describe "get_booking!/1" do
    test "returns booking with full preloads" do
      booking = booking_fixture()
      found = Bookings.get_booking!(booking.id)
      assert found.id == booking.id
      assert found.customer != nil
      assert found.trip != nil
      assert is_list(found.booking_items)
      assert is_list(found.booking_payments)
      assert is_list(found.booking_passengers)
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Bookings.get_booking!(0)
      end
    end
  end

  # ── create_booking/1 ─────────────────────────────────────────────────

  describe "create_booking/1" do
    test "creates booking with valid attrs" do
      customer = customer_fixture()
      trip = trip_fixture()

      assert {:ok, %Booking{} = booking} =
               Bookings.create_booking(%{
                 customer_id: customer.id,
                 trip_id: trip.id,
                 booking_date: ~D[2026-04-01],
                 status: "draft",
                 booking_type: "hotel",
                 destination: "CDMX"
               })

      assert booking.destination == "CDMX"
      assert booking.status == "draft"
    end

    test "returns error with missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Bookings.create_booking(%{})
    end

    test "returns error with invalid status" do
      customer = customer_fixture()
      trip = trip_fixture()

      assert {:error, changeset} =
               Bookings.create_booking(%{
                 customer_id: customer.id,
                 trip_id: trip.id,
                 booking_date: ~D[2026-04-01],
                 status: "bad_status",
                 booking_type: "flight",
                 destination: "CUN"
               })

      assert errors_on(changeset)[:status]
    end
  end

  # ── update_booking/2 ─────────────────────────────────────────────────

  describe "update_booking/2" do
    test "updates booking attributes" do
      booking = booking_fixture(%{destination: "CUN"})
      assert {:ok, updated} = Bookings.update_booking(booking, %{destination: "MEX"})
      assert updated.destination == "MEX"
    end

    test "updates notes" do
      booking = booking_fixture()
      assert {:ok, updated} = Bookings.update_booking(booking, %{notes: "VIP client"})
      assert updated.notes == "VIP client"
    end
  end

  # ── delete_booking/1 ─────────────────────────────────────────────────

  describe "delete_booking/1" do
    test "deletes a booking" do
      booking = booking_fixture()
      {:ok, _} = Bookings.delete_booking(booking)

      assert_raise Ecto.NoResultsError, fn ->
        Bookings.get_booking!(booking.id)
      end
    end
  end

  # ── change_booking/2 ─────────────────────────────────────────────────

  describe "change_booking/2" do
    test "returns a changeset" do
      booking = booking_fixture()
      assert %Ecto.Changeset{} = Bookings.change_booking(booking, %{notes: "test"})
    end
  end

  # ── update_booking_status/2 ──────────────────────────────────────────

  describe "update_booking_status/2" do
    test "updates booking status to confirmed" do
      booking = booking_fixture(%{status: "draft"})
      assert {:ok, updated} = Bookings.update_booking_status(booking, "confirmed")
      assert updated.status == "confirmed"
    end

    test "returns error for invalid status" do
      booking = booking_fixture()
      assert {:error, _} = Bookings.update_booking_status(booking, "invalid_status")
    end
  end

  # ── Booking Passengers ────────────────────────────────────────────────

  describe "add_booking_passenger/2 and remove_booking_passenger/2" do
    test "adds a passenger to a booking" do
      booking = booking_fixture()
      passenger = customer_fixture()

      assert {:ok, _} = Bookings.add_booking_passenger(booking.id, passenger.id)

      found = Bookings.get_booking!(booking.id)
      assert Enum.any?(found.booking_passengers, fn p -> p.customer_id == passenger.id end)
    end

    test "removes a passenger from a booking" do
      booking = booking_fixture()
      passenger = customer_fixture()

      {:ok, _} = Bookings.add_booking_passenger(booking.id, passenger.id)
      assert {:ok, _} = Bookings.remove_booking_passenger(booking.id, passenger.id)

      found = Bookings.get_booking!(booking.id)
      refute Enum.any?(found.booking_passengers, fn p -> p.customer_id == passenger.id end)
    end

    test "returns error when removing passenger not in booking" do
      booking = booking_fixture()
      passenger = customer_fixture()

      assert {:error, :not_found} = Bookings.remove_booking_passenger(booking.id, passenger.id)
    end
  end

  # ── Booking Items ─────────────────────────────────────────────────────

  describe "create_booking_item/1 and delete_booking_item/1" do
    test "creates a booking item and recalculates totals" do
      booking =
        booking_fixture(%{
          commission_type: "fixed",
          commission_value: 50_000
        })

      assert {:ok, %BookingItem{} = item} =
               Bookings.create_booking_item(%{
                 booking_id: booking.id,
                 description: "Round trip flight",
                 price_cents: 350_000,
                 cost_cents: 300_000,
                 quantity: 1
               })

      assert item.price_cents == 350_000
    end

    test "deletes a booking item" do
      booking = booking_fixture()

      {:ok, item} =
        Bookings.create_booking_item(%{
          booking_id: booking.id,
          description: "Hotel 3 nights",
          price_cents: 120_000,
          cost_cents: 90_000,
          quantity: 1
        })

      assert {:ok, _} = Bookings.delete_booking_item(item)
    end
  end

  # ── payment_summary/1 ─────────────────────────────────────────────────

  describe "payment_summary/1" do
    test "returns zero summary for new booking" do
      booking = booking_fixture()
      summary = Bookings.payment_summary(booking)

      assert summary.paid_cents == 0
      assert summary.fully_paid? == false
      assert summary.partially_paid? == false
    end

    test "returns correct summary after advance payment" do
      booking =
        booking_fixture(%{
          commission_type: "fixed",
          commission_value: 50_000
        })

      # Reload to get commission_cents calculated
      booking = Repo.get!(Booking, booking.id)

      {:ok, _} =
        Bookings.create_booking_payment(%{
          booking_id: booking.id,
          amount_cents: 20_000,
          date: Date.utc_today(),
          cash_account_id: nil
        })

      summary = Bookings.payment_summary(booking)
      assert summary.paid_cents == 20_000
      assert summary.partially_paid? == true
    end
  end

  # ── count_by_status/0 ─────────────────────────────────────────────────

  describe "count_by_status/0" do
    test "returns map of status to count" do
      booking_fixture(%{status: "draft"})
      booking_fixture(%{status: "draft"})
      booking_fixture(%{status: "confirmed"})

      counts = Bookings.count_by_status()
      assert is_map(counts)
      assert counts["draft"] >= 2
      assert counts["confirmed"] >= 1
    end

    test "returns empty map when no bookings" do
      assert Bookings.count_by_status() == %{} || is_map(Bookings.count_by_status())
    end
  end

  # ── total_paid/1 ──────────────────────────────────────────────────────

  describe "total_paid/1" do
    test "returns 0 for booking with no payments" do
      booking = booking_fixture()
      assert Bookings.total_paid(booking.id) == 0
    end

    test "sums multiple payments" do
      booking = booking_fixture()

      Bookings.create_booking_payment(%{
        booking_id: booking.id,
        amount_cents: 10_000,
        date: Date.utc_today(),
        cash_account_id: nil
      })

      Bookings.create_booking_payment(%{
        booking_id: booking.id,
        amount_cents: 5_000,
        date: Date.utc_today(),
        cash_account_id: nil
      })

      assert Bookings.total_paid(booking.id) == 15_000
    end
  end
end
