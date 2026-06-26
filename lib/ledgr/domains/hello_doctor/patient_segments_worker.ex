defmodule Ledgr.Domains.HelloDoctor.PatientSegmentsWorker do
  @moduledoc """
  Recomputes the `patient_segments` snapshot (patient tiers L0–L3) once a
  day so the bot always has a reasonably fresh read. The Ledgr UI computes
  tiers live, so this is purely for the materialized snapshot.

  In-process timer, no extra deps — same pattern as `BillingSyncWorker`.
  Only started when the HelloDoctor repo is available (see
  `Ledgr.Application`).
  """

  use GenServer
  require Logger

  alias Ledgr.Domains.HelloDoctor.PatientSegments

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
      counts = PatientSegments.recompute()
      Logger.info("[HelloDoctor.PatientSegmentsWorker] recomputed tiers: #{inspect(counts)}")
    rescue
      e ->
        Logger.error("[HelloDoctor.PatientSegmentsWorker] recompute failed: #{Exception.message(e)}")
    end

    {:noreply, state}
  end

  defp schedule(delay), do: Process.send_after(self(), :recompute, delay)
end
