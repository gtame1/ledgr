defmodule LedgrWeb.Domains.Viaxe.TripHTMLTest do
  use ExUnit.Case, async: true

  alias LedgrWeb.Domains.Viaxe.TripHTML
  alias Ledgr.Domains.Viaxe.Trips.Trip
  alias Ledgr.Domains.Viaxe.Bookings.Booking

  # ── calendar_months/1 ─────────────────────────────────────────────────────

  describe "calendar_months/1" do
    test "returns current month when trip has no dates or bookings" do
      trip = %Trip{start_date: nil, end_date: nil, bookings: []}
      [{year, month}] = TripHTML.calendar_months(trip)
      today = Date.utc_today()
      assert year == today.year
      assert month == today.month
    end

    test "returns single month when trip dates are within the same month" do
      trip = %Trip{start_date: ~D[2026-03-05], end_date: ~D[2026-03-28], bookings: []}
      assert TripHTML.calendar_months(trip) == [{2026, 3}]
    end

    test "returns month range covering trip start through end" do
      trip = %Trip{start_date: ~D[2026-03-10], end_date: ~D[2026-05-20], bookings: []}
      assert TripHTML.calendar_months(trip) == [{2026, 3}, {2026, 4}, {2026, 5}]
    end

    test "handles year boundary correctly" do
      trip = %Trip{start_date: ~D[2025-12-01], end_date: ~D[2026-02-28], bookings: []}
      assert TripHTML.calendar_months(trip) == [{2025, 12}, {2026, 1}, {2026, 2}]
    end

    test "expands range when booking travel_date is outside trip dates" do
      trip = %Trip{
        start_date: ~D[2026-03-01],
        end_date: ~D[2026-03-31],
        bookings: [%Booking{travel_date: ~D[2026-04-15], return_date: nil}]
      }

      result = TripHTML.calendar_months(trip)
      assert {2026, 4} in result
    end

    test "expands range when booking return_date is outside trip dates" do
      trip = %Trip{
        start_date: ~D[2026-03-01],
        end_date: ~D[2026-03-31],
        bookings: [%Booking{travel_date: ~D[2026-03-10], return_date: ~D[2026-05-01]}]
      }

      result = TripHTML.calendar_months(trip)
      assert {2026, 5} in result
    end

    test "ignores nil travel_date and return_date in bookings" do
      trip = %Trip{
        start_date: ~D[2026-03-01],
        end_date: ~D[2026-03-31],
        bookings: [%Booking{travel_date: nil, return_date: nil}]
      }

      assert TripHTML.calendar_months(trip) == [{2026, 3}]
    end

    test "works with only start_date set and no bookings" do
      trip = %Trip{start_date: ~D[2026-06-01], end_date: nil, bookings: []}
      assert TripHTML.calendar_months(trip) == [{2026, 6}]
    end
  end

  # ── calendar_events/1 ─────────────────────────────────────────────────────

  describe "calendar_events/1" do
    test "returns empty map for empty booking list" do
      assert TripHTML.calendar_events([]) == %{}
    end

    test "excludes bookings with nil travel_date" do
      booking = %Booking{travel_date: nil}
      assert TripHTML.calendar_events([booking]) == %{}
    end

    test "groups a single booking under its travel_date" do
      booking = %Booking{travel_date: ~D[2026-03-10]}
      events = TripHTML.calendar_events([booking])
      assert events[~D[2026-03-10]] == [booking]
    end

    test "groups multiple bookings on the same date together" do
      b1 = %Booking{travel_date: ~D[2026-03-10], destination: "Paris"}
      b2 = %Booking{travel_date: ~D[2026-03-10], destination: "Rome"}
      events = TripHTML.calendar_events([b1, b2])
      assert length(events[~D[2026-03-10]]) == 2
    end

    test "creates separate keys for bookings on different dates" do
      b1 = %Booking{travel_date: ~D[2026-03-10]}
      b2 = %Booking{travel_date: ~D[2026-03-15]}
      events = TripHTML.calendar_events([b1, b2])
      assert map_size(events) == 2
      assert Map.has_key?(events, ~D[2026-03-10])
      assert Map.has_key?(events, ~D[2026-03-15])
    end

    test "mixes nil and non-nil travel_dates correctly" do
      b1 = %Booking{travel_date: ~D[2026-03-10]}
      b2 = %Booking{travel_date: nil}
      events = TripHTML.calendar_events([b1, b2])
      assert map_size(events) == 1
    end
  end

  # ── calendar_leading_blanks/2 ─────────────────────────────────────────────

  describe "calendar_leading_blanks/2" do
    # 2026-06-01 is a Monday (day_of_week = 1) → 0 blanks
    test "returns 0 when month starts on Monday" do
      assert TripHTML.calendar_leading_blanks(2026, 6) == 0
    end

    # 2026-03-01 is a Sunday (day_of_week = 7) → 6 blanks
    test "returns 6 when month starts on Sunday" do
      assert TripHTML.calendar_leading_blanks(2026, 3) == 6
    end

    # 2026-04-01 is a Wednesday (day_of_week = 3) → 2 blanks
    test "returns 2 when month starts on Wednesday" do
      assert TripHTML.calendar_leading_blanks(2026, 4) == 2
    end

    test "always returns a value in 0..6" do
      for year <- [2024, 2025, 2026], month <- 1..12 do
        blanks = TripHTML.calendar_leading_blanks(year, month)

        assert blanks in 0..6,
               "Expected 0-6 for #{year}-#{month}, got #{blanks}"
      end
    end

    test "result equals Date.day_of_week minus 1 for the first of the month" do
      for month <- 1..12 do
        expected = Date.day_of_week(Date.new!(2026, month, 1)) - 1
        assert TripHTML.calendar_leading_blanks(2026, month) == expected
      end
    end
  end

  # ── calendar_days_in_month/2 ──────────────────────────────────────────────

  describe "calendar_days_in_month/2" do
    test "returns 31 for months with 31 days" do
      for month <- [1, 3, 5, 7, 8, 10, 12] do
        assert TripHTML.calendar_days_in_month(2026, month) == 31,
               "Expected 31 days for month #{month}"
      end
    end

    test "returns 30 for months with 30 days" do
      for month <- [4, 6, 9, 11] do
        assert TripHTML.calendar_days_in_month(2026, month) == 30,
               "Expected 30 days for month #{month}"
      end
    end

    test "returns 28 for February in a non-leap year" do
      assert TripHTML.calendar_days_in_month(2025, 2) == 28
    end

    test "returns 29 for February in a leap year" do
      assert TripHTML.calendar_days_in_month(2024, 2) == 29
    end

    test "correctly rolls over from December to January" do
      assert TripHTML.calendar_days_in_month(2025, 12) == 31
      assert TripHTML.calendar_days_in_month(2026, 1) == 31
    end
  end

  # ── month_label/2 ─────────────────────────────────────────────────────────

  describe "month_label/2" do
    test "returns formatted month and year string" do
      assert TripHTML.month_label(1, 2026) == "January 2026"
      assert TripHTML.month_label(6, 2026) == "June 2026"
      assert TripHTML.month_label(12, 2025) == "December 2025"
    end

    test "handles all 12 months correctly" do
      month_names = ~w(January February March April May June
                       July August September October November December)

      for {name, index} <- Enum.with_index(month_names, 1) do
        assert TripHTML.month_label(index, 2026) == "#{name} 2026"
      end
    end
  end

  # ── event_icon/1 ──────────────────────────────────────────────────────────

  describe "event_icon/1" do
    test "returns correct emoji for each known booking type" do
      assert TripHTML.event_icon("flight") == "✈️"
      assert TripHTML.event_icon("hotel") == "🏨"
      assert TripHTML.event_icon("tour") == "🗺"
      assert TripHTML.event_icon("transfer") == "🚌"
      assert TripHTML.event_icon("car_rental") == "🚗"
      assert TripHTML.event_icon("cruise") == "🚢"
      assert TripHTML.event_icon("insurance") == "🛡"
    end

    test "returns clipboard icon for other and unknown types" do
      assert TripHTML.event_icon("other") == "📋"
      assert TripHTML.event_icon("unknown_type") == "📋"
      assert TripHTML.event_icon(nil) == "📋"
    end
  end
end
