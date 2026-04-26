defmodule Ledgr.Domains.HelloDoctor.BillingSyncWorker do
  @moduledoc """
  GenServer that pulls external service billing data (OpenAI, Whereby, AWS,
  Evolution) every 15 days and posts the resulting `external_costs` rows to
  the GL.

  Mirrors the `Ledgr.Domains.CasaTame.ExchangeRates.ExchangeRateWorker` pattern:
  in-process timer, no extra deps. Only starts when the HelloDoctor repo is
  available (see `Ledgr.Application`).
  """

  use GenServer
  require Logger

  alias Ledgr.Domains.HelloDoctor.{BillingSync, ExternalCostAccounting}

  @sync_interval :timer.hours(24 * 15)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    schedule_sync(0)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sync, state) do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)

    pull_results = BillingSync.sync_all()
    Logger.info("[HelloDoctor.BillingSyncWorker] sync_all: #{inspect(pull_results)}")

    post_results = ExternalCostAccounting.post_all_unposted()
    Logger.info("[HelloDoctor.BillingSyncWorker] post_all_unposted: #{inspect(post_results)}")

    schedule_sync(@sync_interval)
    {:noreply, state}
  end

  defp schedule_sync(delay) do
    Process.send_after(self(), :sync, delay)
  end
end
