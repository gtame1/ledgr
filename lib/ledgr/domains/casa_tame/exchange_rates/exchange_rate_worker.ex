defmodule Ledgr.Domains.CasaTame.ExchangeRates.ExchangeRateWorker do
  @moduledoc """
  GenServer that fetches and caches the USD→MXN exchange rate daily.
  Only starts when the Casa Tame repo is available.
  """

  use GenServer
  require Logger

  # Fetch once per day (24 hours in milliseconds)
  @fetch_interval :timer.hours(24)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    # Fetch immediately on startup
    schedule_fetch(0)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:fetch_rate, state) do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.CasaTame)

    case Ledgr.Domains.CasaTame.ExchangeRates.fetch_and_cache_rate() do
      {:ok, _rate} ->
        Logger.info("[CasaTame] Exchange rate cached successfully")

      {:error, reason} ->
        Logger.warning(
          "[CasaTame] Exchange rate fetch failed: #{inspect(reason)}, will retry in 1 hour"
        )

        schedule_fetch(:timer.hours(1))
        {:noreply, state}
    end

    schedule_fetch(@fetch_interval)
    {:noreply, state}
  end

  defp schedule_fetch(delay) do
    Process.send_after(self(), :fetch_rate, delay)
  end
end
