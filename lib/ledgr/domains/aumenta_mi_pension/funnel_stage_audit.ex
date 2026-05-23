defmodule Ledgr.Domains.AumentaMiPension.FunnelStageAudit do
  @moduledoc """
  Boot-time drift detector for `Conversations.funnel_stages/0` vs. what
  the bot service has actually been writing to `conversations.funnel_stage`.

  Lives in the supervision tree only when the AMP repo is enabled (see
  `Ledgr.Application`). Schedules a single audit shortly after startup
  so Postgrex has time to fill its pool, logs the result, and then
  sits idle. Add periodic re-checks (cron/Oban) later if catching
  mid-day drift becomes important — for now once-per-boot is enough.

  Audit logic itself lives in `Conversations.audit_funnel_stages/0` so
  it can also be run on demand from iex.
  """

  use GenServer
  require Logger

  alias Ledgr.Domains.AumentaMiPension.Conversations

  # Small delay so the AMP repo's connection pool is ready when we query.
  # Same pattern other AMP workers use to avoid racing the Postgrex boot.
  @initial_delay :timer.seconds(3)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Process.send_after(self(), :audit, @initial_delay)
    {:ok, %{ran_at: nil}}
  end

  @impl true
  def handle_info(:audit, state) do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.AumentaMiPension)

    case safe_audit() do
      {:ok, report} ->
        log_report(report)
        {:noreply, %{state | ran_at: DateTime.utc_now()}}

      {:error, reason} ->
        Logger.warning(
          "[AMP] funnel_stage audit failed: #{inspect(reason)} — " <>
            "skipping (the app keeps running normally)"
        )

        {:noreply, state}
    end
  end

  defp safe_audit do
    {:ok, Conversations.audit_funnel_stages()}
  rescue
    e -> {:error, e}
  end

  defp log_report(%{unknown_in_db: []} = report) do
    Logger.info(
      "[AMP] funnel_stage audit clean — " <>
        "#{length(report.matched)} stages in use, " <>
        "#{length(report.missing_in_db)} declared-but-unused: " <>
        "#{inspect(report.missing_in_db)}"
    )
  end

  defp log_report(%{unknown_in_db: unknown} = _report) do
    Logger.warning(
      "[AMP] funnel_stage DRIFT — the bot is writing values not in our enum: " <>
        "#{inspect(unknown)}. Update " <>
        "Ledgr.Domains.AumentaMiPension.Conversations.funnel_stages/0 " <>
        "and the @funnel_labels map in " <>
        "LedgrWeb.Domains.AumentaMiPension.ConversationListHTML."
    )
  end
end
