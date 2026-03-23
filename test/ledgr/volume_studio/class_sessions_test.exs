defmodule Ledgr.Domains.VolumeStudio.ClassSessionsTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.VolumeStudio.ClassSessions
  alias Ledgr.Domains.VolumeStudio.ClassSessions.{ClassSession, ClassBooking}
  alias Ledgr.Repo

  import Ledgr.Domains.VolumeStudio.Fixtures

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.VolumeStudio)
    Ledgr.Domain.put_current(Ledgr.Domains.VolumeStudio)
    :ok
  end

  describe "list_class_sessions/0" do
    test "returns all non-deleted sessions" do
      session = session_fixture()
      sessions = ClassSessions.list_class_sessions()
      assert Enum.any?(sessions, fn s -> s.id == session.id end)
    end

    test "filters by status" do
      scheduled = session_fixture(%{status: "scheduled"})
      _completed = session_fixture(%{status: "completed"})

      sessions = ClassSessions.list_class_sessions(status: "scheduled")
      assert Enum.any?(sessions, fn s -> s.id == scheduled.id end)
      assert Enum.all?(sessions, fn s -> s.status == "scheduled" end)
    end

    test "filters by from/to datetime" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      future = DateTime.add(now, 7200, :second)
      far_future = DateTime.add(now, 86400, :second)

      soon_session = session_fixture(%{scheduled_at: future})
      _far_session = session_fixture(%{scheduled_at: far_future})

      sessions = ClassSessions.list_class_sessions(
        from: DateTime.add(now, 3600, :second),
        to: DateTime.add(now, 10800, :second)
      )

      assert Enum.any?(sessions, fn s -> s.id == soon_session.id end)
    end

    test "excludes soft-deleted sessions" do
      session = session_fixture()
      {:ok, _} = ClassSessions.delete_class_session(session)

      sessions = ClassSessions.list_class_sessions()
      refute Enum.any?(sessions, fn s -> s.id == session.id end)
    end
  end

  describe "get_class_session!/1" do
    test "returns session with bookings preloaded" do
      session = session_fixture()
      found = ClassSessions.get_class_session!(session.id)
      assert found.id == session.id
      assert is_list(found.class_bookings)
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn ->
        ClassSessions.get_class_session!(0)
      end
    end
  end

  describe "create_class_session/1" do
    test "creates a session with valid attrs" do
      instructor = instructor_fixture()
      scheduled_at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

      attrs = %{
        name: "Power Yoga",
        instructor_id: instructor.id,
        scheduled_at: scheduled_at,
        capacity: 15
      }

      assert {:ok, %ClassSession{} = session} = ClassSessions.create_class_session(attrs)
      assert session.name == "Power Yoga"
    end

    test "returns error with missing required fields" do
      assert {:error, %Ecto.Changeset{}} = ClassSessions.create_class_session(%{})
    end
  end

  describe "update_class_session/2" do
    test "updates session name" do
      session = session_fixture(%{name: "Old Name"})
      assert {:ok, updated} = ClassSessions.update_class_session(session, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "can change status to completed" do
      session = session_fixture(%{status: "scheduled"})
      assert {:ok, updated} = ClassSessions.update_class_session(session, %{status: "completed"})
      assert updated.status == "completed"
    end
  end

  describe "delete_class_session/1" do
    test "soft-deletes session and its bookings" do
      session = session_fixture()
      customer_id = create_test_customer()
      {:ok, booking} = ClassSessions.create_booking(%{
        customer_id: customer_id,
        class_session_id: session.id
      })

      {:ok, _} = ClassSessions.delete_class_session(session)

      sessions = ClassSessions.list_class_sessions()
      refute Enum.any?(sessions, fn s -> s.id == session.id end)

      deleted_booking = Repo.get!(ClassBooking, booking.id)
      assert deleted_booking.deleted_at != nil
    end
  end

  describe "create_booking/1" do
    test "creates a booking with valid attrs" do
      session = session_fixture()
      customer_id = create_test_customer()

      assert {:ok, %ClassBooking{} = booking} = ClassSessions.create_booking(%{
        customer_id: customer_id,
        class_session_id: session.id
      })

      assert booking.status == "booked"
    end

    test "enforces unique constraint (customer + session)" do
      session = session_fixture()
      customer_id = create_test_customer()

      {:ok, _} = ClassSessions.create_booking(%{customer_id: customer_id, class_session_id: session.id})
      assert {:error, changeset} = ClassSessions.create_booking(%{customer_id: customer_id, class_session_id: session.id})
      assert errors_on(changeset)[:customer_id] || errors_on(changeset)[:class_session_id]
    end
  end

  describe "list_bookings_for_session/1" do
    test "returns bookings for a session" do
      session = session_fixture()
      customer_id = create_test_customer()
      {:ok, booking} = ClassSessions.create_booking(%{customer_id: customer_id, class_session_id: session.id})

      bookings = ClassSessions.list_bookings_for_session(session.id)
      assert Enum.any?(bookings, fn b -> b.id == booking.id end)
    end
  end

  describe "checkin/1" do
    test "updates booking status to checked_in" do
      session = session_fixture()
      customer_id = create_test_customer()
      {:ok, booking} = ClassSessions.create_booking(%{customer_id: customer_id, class_session_id: session.id})

      assert {:ok, updated} = ClassSessions.checkin(booking)
      assert updated.status == "checked_in"
    end

    test "increments classes_used on linked subscription" do
      _accounts = vs_accounts_fixture()
      plan = package_plan_fixture()
      customer_id = create_test_customer()
      sub = subscription_fixture(%{customer_id: customer_id, plan: plan})

      session = session_fixture()
      {:ok, booking} = ClassSessions.create_booking(%{
        customer_id: customer_id,
        class_session_id: session.id,
        subscription_id: sub.id
      })

      {:ok, _} = ClassSessions.checkin(booking)

      updated_sub = Repo.get!(Ledgr.Domains.VolumeStudio.Subscriptions.Subscription, sub.id)
      assert updated_sub.classes_used == 1
    end
  end

  describe "mark_attendance/2" do
    test "marks booking as checked_in" do
      session = session_fixture()
      customer_id = create_test_customer()
      {:ok, booking} = ClassSessions.create_booking(%{customer_id: customer_id, class_session_id: session.id})

      assert {:ok, updated} = ClassSessions.mark_attendance(booking, true)
      assert updated.status == "checked_in"
    end

    test "marks booking as no_show" do
      session = session_fixture()
      customer_id = create_test_customer()
      {:ok, booking} = ClassSessions.create_booking(%{customer_id: customer_id, class_session_id: session.id})

      assert {:ok, updated} = ClassSessions.mark_attendance(booking, false)
      assert updated.status == "no_show"
    end

    test "decrements classes_used when un-checking a checked_in booking" do
      _accounts = vs_accounts_fixture()
      plan = package_plan_fixture()
      customer_id = create_test_customer()
      sub = subscription_fixture(%{customer_id: customer_id, plan: plan, deferred_revenue_cents: 0})

      session = session_fixture()
      {:ok, booking} = ClassSessions.create_booking(%{
        customer_id: customer_id,
        class_session_id: session.id,
        subscription_id: sub.id
      })

      # Check in first
      {:ok, checked_in_booking} = ClassSessions.checkin(booking)
      sub_after_checkin = Repo.get!(Ledgr.Domains.VolumeStudio.Subscriptions.Subscription, sub.id)
      assert sub_after_checkin.classes_used == 1

      # Mark as no_show
      {:ok, _} = ClassSessions.mark_attendance(checked_in_booking, false)
      sub_after_noshow = Repo.get!(Ledgr.Domains.VolumeStudio.Subscriptions.Subscription, sub.id)
      assert sub_after_noshow.classes_used == 0
    end
  end

  describe "cancel_booking/1" do
    test "cancels a booking" do
      session = session_fixture()
      customer_id = create_test_customer()
      {:ok, booking} = ClassSessions.create_booking(%{customer_id: customer_id, class_session_id: session.id})

      assert {:ok, cancelled} = ClassSessions.cancel_booking(booking)
      assert cancelled.status == "cancelled"
    end

    test "decrements classes_used when canceling a checked_in booking" do
      _accounts = vs_accounts_fixture()
      plan = package_plan_fixture()
      customer_id = create_test_customer()
      sub = subscription_fixture(%{customer_id: customer_id, plan: plan, deferred_revenue_cents: 0})

      session = session_fixture()
      {:ok, booking} = ClassSessions.create_booking(%{
        customer_id: customer_id,
        class_session_id: session.id,
        subscription_id: sub.id
      })

      {:ok, checked_in} = ClassSessions.checkin(booking)
      sub_mid = Repo.get!(Ledgr.Domains.VolumeStudio.Subscriptions.Subscription, sub.id)
      assert sub_mid.classes_used == 1

      {:ok, _} = ClassSessions.cancel_booking(checked_in)
      sub_final = Repo.get!(Ledgr.Domains.VolumeStudio.Subscriptions.Subscription, sub.id)
      assert sub_final.classes_used == 0
    end
  end

  describe "booking_summary/1" do
    test "returns zero counts for session with no bookings" do
      session = session_fixture(%{capacity: 20})
      summary = ClassSessions.booking_summary(session)

      assert summary.total == 0
      assert summary.booked == 0
      assert summary.checked_in == 0
      assert summary.available == 20
    end

    test "counts bookings by status" do
      session = session_fixture(%{capacity: 20})
      customer_id = create_test_customer()
      {:ok, booking} = ClassSessions.create_booking(%{customer_id: customer_id, class_session_id: session.id})
      {:ok, _} = ClassSessions.checkin(booking)

      customer2_id = create_test_customer()
      {:ok, _} = ClassSessions.create_booking(%{customer_id: customer2_id, class_session_id: session.id})

      summary = ClassSessions.booking_summary(session)
      assert summary.checked_in == 1
      assert summary.booked == 1
      assert summary.total == 2
      assert summary.available == 18
    end

    test "returns nil available when session has no capacity set" do
      session = session_fixture(%{capacity: nil})
      summary = ClassSessions.booking_summary(session)
      assert is_nil(summary.available)
    end
  end

  describe "list_class_sessions_for_calendar_month/2" do
    test "returns sessions grouped by date for given month" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      session = session_fixture(%{scheduled_at: now})

      year = now.year
      month = now.month

      result = ClassSessions.list_class_sessions_for_calendar_month(year, month)
      assert is_map(result)

      date = DateTime.to_date(now)
      sessions_on_date = Map.get(result, date, [])
      assert Enum.any?(sessions_on_date, fn s -> s.id == session.id end)
    end

    test "returns empty map when no sessions in that month" do
      result = ClassSessions.list_class_sessions_for_calendar_month(2000, 1)
      assert result == %{}
    end
  end

  describe "change_booking/2" do
    test "returns a changeset" do
      booking = booking_fixture()
      assert %Ecto.Changeset{} = ClassSessions.change_booking(booking, %{status: "cancelled"})
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp create_test_customer do
    unique = System.unique_integer([:positive])
    {:ok, customer} = Ledgr.Core.Customers.create_customer(%{
      name: "Customer #{unique}",
      phone: "555#{unique}"
    })
    customer.id
  end
end
