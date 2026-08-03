defmodule Ledgr.Domains.HelloDoctor.DailySnapshotWorker do
  @moduledoc """
  Writes `analytics_daily_snapshot` once a day.

  Mirrors the cadence pattern of the other HD workers (supervised GenServer on
  a 24h timer, rescheduled before the work so a crash never stops the loop) —
  Ledgr has no Oban.

  Differs from them in one respect on purpose: **failures are loud**. An
  earlier HD worker swallowed its exception in a `rescue` and left its table
  silently empty, which was only noticed much later. Here, every run logs the
  row count it wrote, a failed run logs at `:error` with a greppable tag, and
  the last outcome is readable via `status/0` so a health check can surface it
  without reading logs. Since this project deliberately has no push
  notifications, a silent failure would otherwise be invisible — an empty
  table reads exactly like a quiet week.
  """

  use GenServer
  require Logger

  alias Ledgr.Domains.HelloDoctor.DailySnapshot

  @interval :timer.hours(24)
  @retry_interval :timer.hours(1)
  # Recompute a trailing window each run: a consultation completed on Monday
  # can have its payment confirmed on Wednesday, changing Monday's row.
  @recompute_days 7

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Last run outcome — `%{last_ok: ..., last_error: ..., rows: ...}`."
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "Force a run now (manual trigger; the scheduled cadence is unaffected)."
  def run_now, do: send(__MODULE__, :snapshot)

  @impl true
  def init(:ok) do
    # Run on boot so a fresh deploy doesn't wait a day for its first row.
    schedule(0)
    {:ok, %{last_ok: nil, last_error: nil, rows: nil}}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info(:snapshot, state) do
    # Reschedule first so a crash never stops the cadence.
    schedule(@interval)

    state =
      try do
        Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)

        {:ok, rows} = run_snapshot()
        total = DailySnapshot.row_count()

        Logger.info(
          "[HD DailySnapshot] wrote #{rows} row(s); #{total} total in analytics_daily_snapshot"
        )

        %{state | last_ok: NaiveDateTime.utc_now(), last_error: nil, rows: rows}
      rescue
        e ->
          # Loud on purpose — see the moduledoc.
          Logger.error(
            "[HD DailySnapshot] FAILED: #{Exception.message(e)}\n" <>
              Exception.format_stacktrace(__STACKTRACE__)
          )

          schedule(@retry_interval)
          %{state | last_error: {NaiveDateTime.utc_now(), Exception.message(e)}}
      end

    {:noreply, state}
  end

  # Empty table = first boot (or a restore). Capture whatever history the bot
  # has not yet deleted; afterwards only the trailing window needs recomputing.
  defp run_snapshot do
    if DailySnapshot.row_count() == 0 do
      Logger.info("[HD DailySnapshot] table empty — backfilling history")
      DailySnapshot.backfill_all()
    else
      DailySnapshot.refresh_recent(@recompute_days)
    end
  end

  defp schedule(delay), do: Process.send_after(self(), :snapshot, delay)
end
