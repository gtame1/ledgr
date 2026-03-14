defmodule Ledgr.Domains.VolumeStudio.ClassSessions do
  @moduledoc """
  Context module for managing Volume Studio class sessions and bookings.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.ClassSessions.{ClassSession, ClassBooking}
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting

  # ── Class Sessions ────────────────────────────────────────────────────

  @doc """
  Returns a list of class sessions.

  Options:
    - `:status` — filter by status string, e.g. "scheduled"
    - `:from` — filter sessions scheduled after this datetime
    - `:to` — filter sessions scheduled before this datetime
  """
  def list_class_sessions(opts \\ []) do
    status = Keyword.get(opts, :status)
    from_dt = Keyword.get(opts, :from)
    to_dt = Keyword.get(opts, :to)

    ClassSession
    |> maybe_filter_status(status)
    |> maybe_filter_from(from_dt)
    |> maybe_filter_to(to_dt)
    |> order_by(desc: :scheduled_at)
    |> preload(:instructor)
    |> Repo.all()
  end

  @doc "Gets a single class session with instructor and bookings preloaded. Raises if not found."
  def get_class_session!(id) do
    ClassSession
    |> preload([:instructor, class_bookings: [:customer, :subscription]])
    |> Repo.get!(id)
  end

  @doc "Returns a changeset for the given session and attrs."
  def change_class_session(%ClassSession{} = session, attrs \\ %{}) do
    ClassSession.changeset(session, attrs)
  end

  @doc "Creates a class session."
  def create_class_session(attrs \\ %{}) do
    %ClassSession{}
    |> ClassSession.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a class session."
  def update_class_session(%ClassSession{} = session, attrs) do
    session
    |> ClassSession.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a class session."
  def delete_class_session(%ClassSession{} = session) do
    Repo.delete(session)
  end

  # ── Bookings ──────────────────────────────────────────────────────────

  @doc "Returns all bookings for the given session_id with customer preloaded."
  def list_bookings_for_session(session_id) do
    ClassBooking
    |> where(class_session_id: ^session_id)
    |> preload([:customer, :subscription])
    |> Repo.all()
  end

  @doc "Returns a changeset for the given booking and attrs."
  def change_booking(%ClassBooking{} = booking, attrs \\ %{}) do
    ClassBooking.changeset(booking, attrs)
  end

  @doc "Creates a booking. Enforces unique constraint (customer + session)."
  def create_booking(attrs \\ %{}) do
    %ClassBooking{}
    |> ClassBooking.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Checks in a booking.

  In a transaction:
    1. Updates booking.status → "checked_in"
    2. If booking.subscription_id present → increments subscription.classes_used
    3. If booking.paid_cents > 0 → creates class payment journal entry
  """
  def checkin(%ClassBooking{} = booking) do
    Repo.transaction(fn ->
      updated =
        booking
        |> ClassBooking.changeset(%{status: "checked_in"})
        |> Repo.update!()

      # Increment classes_used on subscription if applicable
      if updated.subscription_id do
        sub = Repo.get!(Subscription, updated.subscription_id)

        sub
        |> Ecto.Changeset.change(classes_used: sub.classes_used + 1)
        |> Repo.update!()
      end

      # Record class payment journal entry if a fee was paid
      if updated.paid_cents > 0 do
        VolumeStudioAccounting.record_class_payment(updated)
      end

      updated
    end)
  end

  @doc """
  Cancels a booking by updating its status.

  If the booking was already checked in, decrements `classes_used` on the linked
  subscription so the counter stays accurate.
  """
  def cancel_booking(%ClassBooking{} = booking) do
    Repo.transaction(fn ->
      updated =
        booking
        |> ClassBooking.changeset(%{status: "cancelled"})
        |> Repo.update!()

      if booking.status == "checked_in" && booking.subscription_id do
        sub = Repo.get!(Subscription, booking.subscription_id)

        sub
        |> Ecto.Changeset.change(classes_used: max(sub.classes_used - 1, 0))
        |> Repo.update!()
      end

      updated
    end)
  end

  @doc """
  Returns a booking summary map for a session.

  Keys: :total, :booked, :checked_in, :no_show, :cancelled, :available
  """
  def booking_summary(%ClassSession{} = session) do
    bookings =
      ClassBooking
      |> where(class_session_id: ^session.id)
      |> Repo.all()

    counts = Enum.frequencies_by(bookings, & &1.status)

    booked = Map.get(counts, "booked", 0)
    checked_in = Map.get(counts, "checked_in", 0)
    no_show = Map.get(counts, "no_show", 0)
    cancelled = Map.get(counts, "cancelled", 0)
    total = booked + checked_in + no_show + cancelled

    available =
      if session.capacity do
        max(session.capacity - booked - checked_in, 0)
      else
        nil
      end

    %{
      total: total,
      booked: booked,
      checked_in: checked_in,
      no_show: no_show,
      cancelled: cancelled,
      available: available
    }
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp maybe_filter_from(query, nil), do: query
  defp maybe_filter_from(query, dt), do: where(query, [s], s.scheduled_at >= ^dt)

  defp maybe_filter_to(query, nil), do: query
  defp maybe_filter_to(query, dt), do: where(query, [s], s.scheduled_at <= ^dt)
end
