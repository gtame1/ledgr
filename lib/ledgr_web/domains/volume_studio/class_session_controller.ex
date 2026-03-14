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

    subs_by_customer =
      Subscriptions.list_subscriptions(status: "active")
      |> Enum.group_by(&to_string(&1.customer_id))
      |> Map.new(fn {cid, subs} ->
        {cid, Enum.map(subs, &%{id: &1.id, name: &1.subscription_plan.name})}
      end)

    render(conn, :new_booking,
      session:           session,
      customers:         customers,
      subs_by_customer:  subs_by_customer,
      action:            dp(conn, "/class-sessions/#{session_id}/bookings")
    )
  end

  def create_booking(conn, %{"id" => session_id, "booking" => params}) do
    session = ClassSessions.get_class_session!(session_id)

    paid_cents =
      case Float.parse(params["paid_cents"] || "0") do
        {v, _} -> round(v * 100)
        :error  -> 0
      end

    subscription_id =
      case params["subscription_id"] do
        "" -> nil
        id -> id
      end

    attrs = %{
      class_session_id: session.id,
      customer_id:      params["customer_id"],
      subscription_id:  subscription_id,
      paid_cents:       max(0, paid_cents),
      status:           "booked"
    }

    case ClassSessions.create_booking(attrs) do
      {:ok, _booking} ->
        conn
        |> put_flash(:info, "Member booked successfully.")
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

  def checkin(conn, %{"id" => session_id, "booking_id" => booking_id}) do
    session = ClassSessions.get_class_session!(session_id)
    booking = Enum.find(session.class_bookings, &(to_string(&1.id) == booking_id))

    if booking do
      case ClassSessions.checkin(booking) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Checked in successfully.")
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

  def format_datetime(%DateTime{} = dt),
    do: Calendar.strftime(dt, "%b %-d, %Y · %-I:%M %p")

  def format_datetime(%NaiveDateTime{} = ndt),
    do: Calendar.strftime(ndt, "%b %-d, %Y · %-I:%M %p")

  def format_datetime(nil), do: "—"
  def format_datetime(other), do: to_string(other)
end
