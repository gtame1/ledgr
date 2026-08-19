defmodule Ledgr.Domains.HelloDoctor.ExchangeRateWorker do
  @moduledoc """
  GenServer that refreshes the USD→MXN rate cached in HelloDoctor's
  `app_settings` table once a day.

  ExternalCostAccounting reads this rate (via `Ledgr.Core.Settings.get_usd_mxn_rate/0`)
  when converting OpenAI/Whereby/AWS costs to MXN journal entries. Without
  this worker the rate stays at the hardcoded fallback of 17.5 forever,
  which is fine in stable markets but stale otherwise.

  Writes to HelloDoctor's repo via the Settings key/value store rather than
  a dedicated `exchange_rates` table.
  """

  use GenServer
  require Logger

  alias Ledgr.Core.Settings

  @fetch_interval :timer.hours(24)
  @retry_interval :timer.hours(1)
  # frankfurter.app moved to frankfurter.dev/v1/ in 2026 — the .app domain
  # 301-redirects but is unreliable through some clients.
  @api_url "https://api.frankfurter.dev/v1/latest?from=USD&to=MXN"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    # Fetch immediately on startup so a fresh boot doesn't run on stale data
    schedule_fetch(0)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:fetch_rate, state) do
    # Always reschedule first so a crash never stops the cadence.
    schedule_fetch(@fetch_interval)

    try do
      Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)

      case fetch_rate() do
        {:ok, rate} ->
          Settings.set_usd_mxn_rate(rate)
          Logger.info("[HelloDoctor ExchangeRateWorker] Cached USD→MXN rate: #{rate}")

        {:error, reason} ->
          Logger.warning(
            "[HelloDoctor ExchangeRateWorker] Fetch failed: #{inspect(reason)} — " <>
              "retrying in 1 hour"
          )

          # Retry sooner than the normal cadence
          schedule_fetch(@retry_interval)
      end
    rescue
      e ->
        Logger.error(
          "[HelloDoctor ExchangeRateWorker] Unexpected error: #{Exception.message(e)}"
        )
    end

    {:noreply, state}
  end

  defp fetch_rate do
    case Req.get(@api_url) do
      {:ok, %{status: 200, body: %{"rates" => %{"MXN" => rate}}}} when is_number(rate) ->
        {:ok, rate * 1.0}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule_fetch(delay) do
    Process.send_after(self(), :fetch_rate, delay)
  end
end
