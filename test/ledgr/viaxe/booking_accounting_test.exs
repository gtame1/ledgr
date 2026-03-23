defmodule Ledgr.Domains.Viaxe.Bookings.BookingAccountingTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.Viaxe.Bookings
  alias Ledgr.Domains.Viaxe.Bookings.{Booking, BookingAccounting}
  alias Ledgr.Domains.Viaxe.Customers
  alias Ledgr.Domains.Viaxe.Trips
  alias Ledgr.Core.Accounting
  alias Ledgr.Repo

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)
    Ledgr.Domain.put_current(Ledgr.Domains.Viaxe)

    accounts = [
      %{code: "1000", name: "Cash",                  type: "asset",     normal_balance: "debit",  is_cash: true},
      %{code: "1100", name: "Commission Receivable",  type: "asset",     normal_balance: "debit",  is_cash: false},
      %{code: "2200", name: "Advance Commission",     type: "liability", normal_balance: "credit", is_cash: false},
      %{code: "4000", name: "Commission Revenue",     type: "revenue",   normal_balance: "credit", is_cash: false}
    ]

    Enum.each(accounts, fn attrs ->
      case Accounting.get_account_by_code(attrs.code) do
        nil -> {:ok, _} = Accounting.create_account(attrs)
        _   -> :ok
      end
    end)

    :ok
  end

  defp customer_fixture do
    unique = System.unique_integer([:positive])
    {:ok, c} = Customers.create_customer(%{first_name: "T", last_name: "C#{unique}", phone: "+52551#{unique}"})
    c
  end

  defp trip_fixture do
    {:ok, t} = Trips.create_trip(%{title: "Trip #{System.unique_integer([:positive])}", start_date: ~D[2026-08-01], status: "planning"})
    t
  end

  defp booking_fixture(attrs \\ %{}) do
    customer = customer_fixture()
    trip = trip_fixture()

    {:ok, booking} =
      Bookings.create_booking(
        Enum.into(attrs, %{
          customer_id: customer.id,
          trip_id: trip.id,
          booking_date: ~D[2026-03-01],
          status: "draft",
          booking_type: "flight",
          destination: "CUN",
          commission_type: "fixed",
          commission_value: 50_000
        })
      )

    booking
  end

  # ── handle_status_change/2 ───────────────────────────────────────────

  describe "handle_status_change/2" do
    test "returns {:ok, nil} for unknown status" do
      assert {:ok, nil} = BookingAccounting.handle_status_change(%{}, "draft")
    end

    test "returns {:ok, nil} for in_progress status" do
      assert {:ok, nil} = BookingAccounting.handle_status_change(%{}, "in_progress")
    end
  end

  # ── record_booking_payment/1 ─────────────────────────────────────────

  describe "record_booking_payment/1" do
    test "creates advance payment entry when booking is not completed" do
      booking = booking_fixture(%{status: "draft"})

      {:ok, payment} =
        Bookings.create_booking_payment(%{
          booking_id: booking.id,
          amount_cents: 20_000,
          date: Date.utc_today()
        })

      # Payment was created and accounting entry recorded
      assert payment.is_advance == true
      assert payment.amount_cents == 20_000
    end

    test "creates settlement entry when booking is completed" do
      booking = booking_fixture(%{status: "completed"})

      {:ok, payment} =
        Bookings.create_booking_payment(%{
          booking_id: booking.id,
          amount_cents: 30_000,
          date: Date.utc_today()
        })

      assert payment.is_advance == false
    end
  end

  # ── record_booking_completed/1 ───────────────────────────────────────

  describe "record_booking_completed/1" do
    test "creates revenue recognition entry" do
      booking = booking_fixture()
      # Reload to get commission_cents
      booking = Repo.get!(Booking, booking.id)

      {:ok, entry} = BookingAccounting.record_booking_completed(booking)

      assert entry.entry_type == "booking_completed"
      assert entry.reference == "viaxe_booking_#{booking.id}_completed"
    end

    test "is idempotent" do
      booking = booking_fixture()
      booking = Repo.get!(Booking, booking.id)

      {:ok, entry1} = BookingAccounting.record_booking_completed(booking)
      {:ok, entry2} = BookingAccounting.record_booking_completed(booking)

      assert entry1.id == entry2.id
    end

    test "includes advance debit when advance payments exist" do
      booking = booking_fixture(%{status: "draft"})

      # Record an advance payment
      Bookings.create_booking_payment(%{
        booking_id: booking.id,
        amount_cents: 20_000,
        date: Date.utc_today()
      })

      booking = Repo.get!(Booking, booking.id)
      {:ok, entry} = BookingAccounting.record_booking_completed(booking)

      lines = Repo.preload(entry, :journal_lines).journal_lines
      total_debits = Enum.reduce(lines, 0, fn l, acc -> acc + l.debit_cents end)
      total_credits = Enum.reduce(lines, 0, fn l, acc -> acc + l.credit_cents end)

      assert total_debits == total_credits
    end
  end

  # ── record_booking_canceled/1 ────────────────────────────────────────

  describe "record_booking_canceled/1" do
    test "returns {:ok, nil} when booking was not completed" do
      booking = booking_fixture(%{status: "draft"})
      booking = Repo.get!(Booking, booking.id)

      assert {:ok, nil} = BookingAccounting.record_booking_canceled(booking)
    end

    test "creates reversal entry when booking was completed" do
      booking = booking_fixture(%{status: "completed"})
      booking = Repo.get!(Booking, booking.id)

      # First complete it to create revenue
      {:ok, _} = BookingAccounting.record_booking_completed(booking)

      {:ok, entry} = BookingAccounting.record_booking_canceled(booking)

      assert entry.entry_type == "booking_canceled"

      lines = Repo.preload(entry, :journal_lines).journal_lines
      total_debits = Enum.reduce(lines, 0, fn l, acc -> acc + l.debit_cents end)
      total_credits = Enum.reduce(lines, 0, fn l, acc -> acc + l.credit_cents end)
      assert total_debits == total_credits
    end
  end
end
