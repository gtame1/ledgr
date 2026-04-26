defmodule LedgrWeb.Domains.VolumeStudio.ClassSessionController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.ClassSessions
  alias Ledgr.Domains.VolumeStudio.ClassSessions.ClassSession
  alias Ledgr.Domains.VolumeStudio.Instructors
  alias Ledgr.Core.Customers
  alias Ledgr.Domains.VolumeStudio.Subscriptions

  def index(conn, params) do
    status = params["status"]
    sessions = ClassSessions.list_class_sessions(status: status)
    render(conn, :index, sessions: sessions, current_status: status)
  end

  def show(conn, %{"id" => id}) do
    session = ClassSessions.get_class_session!(id)
    summary = ClassSessions.booking_summary(session)
    render(conn, :show, session: session, summary: summary)
  end

  def new(conn, _params) do
    changeset = ClassSessions.change_class_session(%ClassSession{})
    instructors = Instructors.list_active_instructors()
    render(conn, :new,
      changeset: changeset,
      instructors: instructors,
      action: dp(conn, "/class-sessions")
    )
  end

  def create(conn, %{"class_session" => params}) do
    case ClassSessions.create_class_session(params) do
      {:ok, session} ->
        conn
        |> put_flash(:info, "Class session created.")
        |> redirect(to: dp(conn, "/class-sessions/#{session.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        instructors = Instructors.list_active_instructors()
        render(conn, :new,
          changeset: changeset,
          instructors: instructors,
          action: dp(conn, "/class-sessions")
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    session = ClassSessions.get_class_session!(id)
    changeset = ClassSessions.change_class_session(session)
    instructors = Instructors.list_active_instructors()
    render(conn, :edit,
      session: session,
      changeset: changeset,
      instructors: instructors,
      action: dp(conn, "/class-sessions/#{id}")
    )
  end

  def update(conn, %{"id" => id, "class_session" => params}) do
    session = ClassSessions.get_class_session!(id)

    case ClassSessions.update_class_session(session, params) do
      {:ok, session} ->
        conn
        |> put_flash(:info, "Class session updated.")
        |> redirect(to: dp(conn, "/class-sessions/#{session.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        instructors = Instructors.list_active_instructors()
        render(conn, :edit,
          session: session,
          changeset: changeset,
          instructors: instructors,
          action: dp(conn, "/class-sessions/#{id}")
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    session = ClassSessions.get_class_session!(id)

    case ClassSessions.delete_class_session(session) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Class session deleted.")
        |> redirect(to: dp(conn, "/class-sessions"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Cannot delete — session has bookings.")
        |> redirect(to: dp(conn, "/class-sessions/#{id}"))
    end
  end

  def new_booking(conn, %{"id" => session_id}) do
    session = ClassSessions.get_class_session!(session_id)

    customers =
      Customers.list_customers()
      |> Enum.map(&{"#{&1.name} (#{&1.phone})", &1.id})

    render(conn, :new_booking,
      session:   session,
      customers: customers,
      action:    dp(conn, "/class-sessions/#{session_id}/bookings")
    )
  end

  def create_booking(conn, %{"id" => session_id, "booking" => params}) do
    session     = ClassSessions.get_class_session!(session_id)
    customer_id = params["customer_id"]

    # Auto-assign the subscription closest to expiring that still has classes available.
    # A subscription is required — all class attendance is subscription-based.
    target_sub = Subscriptions.get_soonest_expiring_subscription(customer_id)

    attrs = %{
      class_session_id: session.id,
      customer_id:      customer_id,
      subscription_id:  target_sub && target_sub.id,
      status:           "booked"
    }

    case ClassSessions.create_booking(attrs) do
      {:ok, _booking} ->
        msg =
          if target_sub do
            "Member booked and counted under \"#{target_sub.subscription_plan.name}\" (expires #{target_sub.ends_on})."
          else
            "Member booked (no active subscription found — assign one before check-in)."
          end

        conn
        |> put_flash(:info, msg)
        |> redirect(to: dp(conn, "/class-sessions/#{session_id}"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not create booking. The member may already be booked for this session.")
        |> redirect(to: dp(conn, "/class-sessions/#{session_id}/bookings/new"))
    end
  end

  def cancel_booking(conn, %{"id" => session_id, "booking_id" => booking_id}) do
    session = ClassSessions.get_class_session!(session_id)
    booking = Enum.find(session.class_bookings, &(to_string(&1.id) == booking_id))

    result = booking && ClassSessions.cancel_booking(booking)

    case result do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Booking cancelled.")
        |> redirect(to: dp(conn, "/class-sessions/#{session_id}"))

      _ ->
        conn
        |> put_flash(:error, "Could not cancel booking.")
        |> redirect(to: dp(conn, "/class-sessions/#{session_id}"))
    end
  end

  def update_status(conn, %{"id" => id, "status" => status}) do
    session = ClassSessions.get_class_session!(id)

    case ClassSessions.update_class_session(session, %{status: status}) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Session marked as #{status}.")
        |> redirect(to: dp(conn, "/class-sessions/#{id}"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not update session status.")
        |> redirect(to: dp(conn, "/class-sessions/#{id}"))
    end
  end

  def calendar(conn, params) do
    today = today_mx()

    year = case params["year"] do
      nil -> today.year
      y   -> String.to_integer(y)
    end

    month = case params["month"] do
      nil -> today.month
      m   -> String.to_integer(m)
    end

    month = cond do
      month < 1  -> 1
      month > 12 -> 12
      true       -> month
    end

    sessions_by_date = ClassSessions.list_class_sessions_for_calendar_month(year, month)

    first_day = Date.new!(year, month, 1)
    last_day  = Date.end_of_month(first_day)

    weekday         = Date.day_of_week(first_day)
    days_from_sunday = if weekday == 7, do: 0, else: weekday
    calendar_start  = Date.add(first_day, -days_from_sunday)
    calendar_end    = Date.add(calendar_start, 41)

    render(conn, :calendar,
      year:             year,
      month:            month,
      first_day:        first_day,
      last_day:         last_day,
      calendar_start:   calendar_start,
      calendar_end:     calendar_end,
      sessions_by_date: sessions_by_date,
      today:            today
    )
  end

  def mark_attendance(conn, %{"id" => session_id, "booking_id" => booking_id, "attended" => attended_str}) do
    session = ClassSessions.get_class_session!(session_id)
    booking = Enum.find(session.class_bookings, &(to_string(&1.id) == booking_id))
    attended = attended_str == "true"

    if booking do
      case ClassSessions.mark_attendance(booking, attended) do
        {:ok, _} ->
          label = if attended, do: "checked in", else: "marked as no-show"

          conn
          |> put_flash(:info, "#{booking.customer.name} #{label}.")
          |> redirect(to: dp(conn, "/class-sessions/#{session_id}"))

        {:error, :class_limit_reached} ->
          conn
          |> put_flash(:error, "Class limit reached for this subscription.")
          |> redirect(to: dp(conn, "/class-sessions/#{session_id}"))

        {:error, reason} ->
          conn
          |> put_flash(:error, "Could not update attendance: #{inspect(reason)}")
          |> redirect(to: dp(conn, "/class-sessions/#{session_id}"))
      end
    else
      conn
      |> put_flash(:error, "Booking not found.")
      |> redirect(to: dp(conn, "/class-sessions/#{session_id}"))
    end
  end

  def checkin(conn, %{"id" => session_id, "booking_id" => booking_id}) do
    session = ClassSessions.get_class_session!(session_id)
    booking = Enum.find(session.class_bookings, &(to_string(&1.id) == booking_id))

    if booking do
      case ClassSessions.checkin(booking) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Checked in successfully.")
          |> redirect(to: dp(conn, "/class-sessions/#{session_id}"))

        {:error, :class_limit_reached} ->
          conn
          |> put_flash(:error, "Class limit reached for this subscription.")
          |> redirect(to: dp(conn, "/class-sessions/#{session_id}"))

        {:error, reason} ->
          conn
          |> put_flash(:error, "Check-in failed: #{inspect(reason)}")
          |> redirect(to: dp(conn, "/class-sessions/#{session_id}"))
      end
    else
      conn
      |> put_flash(:error, "Booking not found.")
      |> redirect(to: dp(conn, "/class-sessions/#{session_id}"))
    end
  end
end

defmodule LedgrWeb.Domains.VolumeStudio.ClassSessionHTML do
  use LedgrWeb, :html

  embed_templates "class_session_html/*"

  def status_class("scheduled"), do: "status-partial"
  def status_class("completed"), do: "status-paid"
  def status_class("cancelled"), do: "status-unpaid"
  def status_class(_), do: ""

  def booking_status_class("booked"), do: "status-partial"
  def booking_status_class("checked_in"), do: "status-paid"
  def booking_status_class("no_show"), do: "status-unpaid"
  def booking_status_class("cancelled"), do: "status-unpaid"
  def booking_status_class(_), do: ""

  def humanize_booking_status("checked_in"), do: "Checked In"
  def humanize_booking_status("no_show"), do: "No Show"
  def humanize_booking_status(s), do: String.capitalize(s)

  def prev_month(year, month) do
    if month == 1, do: %{year: year - 1, month: 12}, else: %{year: year, month: month - 1}
  end

  def next_month(year, month) do
    if month == 12, do: %{year: year + 1, month: 1}, else: %{year: year, month: month + 1}
  end

  def format_time(nil),                    do: ""
  def format_time(%DateTime{} = dt),       do: fmt_time(dt, "%-I:%M %p")
  def format_time(%NaiveDateTime{} = ndt), do: fmt_time(ndt, "%-I:%M %p")
  def format_time(_),                      do: ""

  def format_datetime(nil), do: "—"
  def format_datetime(%DateTime{} = dt), do: fmt_datetime(dt, "%b %-d, %Y · %-I:%M %p")
  def format_datetime(%NaiveDateTime{} = ndt), do: fmt_datetime(ndt, "%b %-d, %Y · %-I:%M %p")
  def format_datetime(other), do: to_string(other)
end
