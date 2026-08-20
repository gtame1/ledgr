defmodule Ledgr.Domains.Viaxe.TripsTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.Viaxe.Trips
  alias Ledgr.Domains.Viaxe.Trips.Trip
  alias Ledgr.Domains.Viaxe.Customers

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)
    Ledgr.Domain.put_current(Ledgr.Domains.Viaxe)
    :ok
  end

  defp trip_fixture(attrs \\ %{}) do
    {:ok, trip} =
      Trips.create_trip(
        Enum.into(attrs, %{
          title: "Trip #{System.unique_integer([:positive])}",
          start_date: ~D[2026-08-01],
          end_date: ~D[2026-08-10],
          status: "planning"
        })
      )

    trip
  end

  defp customer_fixture do
    unique = System.unique_integer([:positive])

    {:ok, customer} =
      Customers.create_customer(%{
        first_name: "Test",
        last_name: "Customer #{unique}",
        phone: "+52551#{unique}"
      })

    customer
  end

  describe "list_trips/1" do
    test "returns all trips" do
      trip = trip_fixture()
      assert Enum.any?(Trips.list_trips(), fn t -> t.id == trip.id end)
    end

    test "filters by status" do
      _planning = trip_fixture(%{status: "planning"})
      active = trip_fixture(%{status: "active"})

      trips = Trips.list_trips(status: "active")
      assert Enum.any?(trips, fn t -> t.id == active.id end)
      assert Enum.all?(trips, fn t -> t.status == "active" end)
    end

    test "orders by start_date descending" do
      trip_fixture(%{start_date: ~D[2026-06-01], end_date: ~D[2026-06-10]})
      trip_fixture(%{start_date: ~D[2026-09-01], end_date: ~D[2026-09-10]})

      trips = Trips.list_trips()
      dates = Enum.map(trips, & &1.start_date)
      assert dates == Enum.sort(dates, {:desc, Date})
    end
  end

  describe "get_trip!/1" do
    test "returns trip with preloads" do
      trip = trip_fixture()
      found = Trips.get_trip!(trip.id)
      assert found.id == trip.id
      assert is_list(found.passengers)
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn -> Trips.get_trip!(0) end
    end
  end

  describe "create_trip/1" do
    test "creates trip with valid attrs" do
      assert {:ok, %Trip{} = trip} =
               Trips.create_trip(%{
                 title: "Cancún Escape",
                 start_date: ~D[2026-07-01],
                 status: "planning"
               })

      assert trip.title == "Cancún Escape"
    end

    test "returns error with missing title" do
      assert {:error, %Ecto.Changeset{}} = Trips.create_trip(%{})
    end
  end

  describe "update_trip/2" do
    test "updates trip attributes" do
      trip = trip_fixture(%{title: "Old Title"})
      assert {:ok, updated} = Trips.update_trip(trip, %{title: "New Title"})
      assert updated.title == "New Title"
    end
  end

  describe "delete_trip/1" do
    test "deletes a trip" do
      trip = trip_fixture()
      {:ok, _} = Trips.delete_trip(trip)
      assert_raise Ecto.NoResultsError, fn -> Trips.get_trip!(trip.id) end
    end
  end

  describe "change_trip/2" do
    test "returns a changeset" do
      trip = trip_fixture()
      assert %Ecto.Changeset{} = Trips.change_trip(trip, %{title: "Changed"})
    end
  end

  describe "trip_select_options/0" do
    test "returns list of {title, id} tuples" do
      trip = trip_fixture(%{title: "Beach Trip"})
      options = Trips.trip_select_options()
      assert Enum.any?(options, fn {title, id} -> title == "Beach Trip" and id == trip.id end)
    end
  end

  describe "add_passenger/3 and remove_passenger/2" do
    test "adds a passenger to a trip" do
      trip = trip_fixture()
      customer = customer_fixture()

      assert {:ok, _} = Trips.add_passenger(trip.id, customer.id)
      found = Trips.get_trip!(trip.id)
      assert Enum.any?(found.trip_passengers, fn tp -> tp.customer_id == customer.id end)
    end

    test "adds a primary contact passenger" do
      trip = trip_fixture()
      customer = customer_fixture()

      assert {:ok, tp} = Trips.add_passenger(trip.id, customer.id, is_primary_contact: true)
      assert tp.is_primary_contact == true
    end

    test "removes a passenger" do
      trip = trip_fixture()
      customer = customer_fixture()

      {:ok, _} = Trips.add_passenger(trip.id, customer.id)
      assert {:ok, _} = Trips.remove_passenger(trip.id, customer.id)
    end

    test "returns error when removing non-existent passenger" do
      trip = trip_fixture()
      customer = customer_fixture()
      assert {:error, :not_found} = Trips.remove_passenger(trip.id, customer.id)
    end
  end

  describe "booking_count/1" do
    test "returns 0 for trip with no bookings" do
      trip = trip_fixture()
      assert Trips.booking_count(trip) == 0
    end
  end
end
