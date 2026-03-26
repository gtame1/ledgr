defmodule Ledgr.Domains.MrMunchMe.PendingCheckoutRecovery do
  @moduledoc """
  Background worker that periodically checks for PendingCheckouts that were paid
  in Stripe but never had orders created (e.g. webhook missed + customer closed
  browser before seeing the success page).

  Runs every 5 minutes. For each unprocessed checkout older than 10 minutes with
  a Stripe session ID, it retrieves the session from Stripe and creates orders if
  payment_status == "paid".
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias Ledgr.Domains.MrMunchMe.{Orders, PendingCheckouts, PendingCheckout}
  alias Ledgr.Repos.MrMunchMe, as: Repo

  @interval_ms :timer.minutes(5)
  # Only look at checkouts that are at least this old, to avoid racing with
  # in-flight webhooks that haven't been delivered yet.
  @min_age_minutes 10

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_next_run()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:run, state) do
    recover_unprocessed()
    schedule_next_run()
    {:noreply, state}
  end

  @doc "Manually trigger a recovery pass. Useful for testing or one-off runs."
  def recover_unprocessed do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -@min_age_minutes * 60, :second)

    unprocessed =
      Repo.all(
        from pc in PendingCheckout,
          where:
            not is_nil(pc.stripe_session_id) and
              is_nil(pc.processed_at) and
              pc.inserted_at < ^cutoff
      )

    if unprocessed != [] do
      Logger.info("[PendingCheckoutRecovery] Found #{length(unprocessed)} unprocessed checkout(s) to check")
    end

    Enum.each(unprocessed, &maybe_recover/1)
  end

  defp maybe_recover(pending) do
    case Stripe.Checkout.Session.retrieve(pending.stripe_session_id) do
      {:ok, session} when session.payment_status == "paid" ->
        Logger.info("[PendingCheckoutRecovery] Recovering order for pending checkout #{pending.id}")

        case Orders.create_orders_from_pending_checkout(pending, pending.stripe_session_id) do
          {:ok, orders} ->
            PendingCheckouts.mark_processed(pending)
            Logger.info("[PendingCheckoutRecovery] Created #{length(orders)} order(s) for pending checkout #{pending.id}")

          {:error, reason} ->
            Logger.error("[PendingCheckoutRecovery] Failed to create orders for pending checkout #{pending.id}: #{inspect(reason)}")
        end

      {:ok, _session} ->
        # Not paid yet — leave it for the next pass or until it expires
        :ok

      {:error, reason} ->
        Logger.warning("[PendingCheckoutRecovery] Could not retrieve Stripe session #{pending.stripe_session_id}: #{inspect(reason)}")
    end
  end

  defp schedule_next_run do
    Process.send_after(self(), :run, @interval_ms)
  end
end
