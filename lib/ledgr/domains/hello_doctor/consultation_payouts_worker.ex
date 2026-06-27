defmodule Ledgr.Domains.HelloDoctor.ConsultationPayoutsWorker do
  @moduledoc """
  Freezes the doctor share for newly-billed consultations once a day (and on
  boot) into `consultation_payouts`. The Ledgr UI also freezes lazily on
  page view, so this is the catch-all sweep.

  In-process timer, same pattern as `PatientSegmentsWorker`. Only started
  when the HelloDoctor repo is available (see `Ledgr.Application`).
  """

  use GenServer
  require Logger

  alias Ledgr.Domains.HelloDoctor.ConsultationPayouts

  @interval :timer.hours(24)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    schedule(0)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:recompute, state) do
    # Reschedule first so a crash never stops the daily cadence.
    schedule(@interval)

    try do
      Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)
      inserted = ConsultationPayouts.recompute()
      Logger.info("[HelloDoctor.ConsultationPayoutsWorker] froze #{inserted} new consultation payout(s)")
    rescue
      e ->
        Logger.error(
          "[HelloDoctor.ConsultationPayoutsWorker] recompute failed: #{Exception.message(e)}"
        )
    end

    {:noreply, state}
  end

  defp schedule(delay), do: Process.send_after(self(), :recompute, delay)
end
