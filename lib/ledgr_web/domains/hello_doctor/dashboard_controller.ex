defmodule LedgrWeb.Domains.HelloDoctor.DashboardController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.BillingSync

  def index(conn, _params) do
    today = Ledgr.Domains.HelloDoctor.today()
    start_date = Date.beginning_of_month(today)
    end_date = today
    metrics = Ledgr.Domains.HelloDoctor.dashboard_metrics(start_date, end_date)

    conn
    |> assign(:page_title, "Dashboard")
    |> render(:index, Map.to_list(metrics))
  end

  def sync_costs(conn, _params) do
    results = BillingSync.sync_all()

    messages =
      Enum.flat_map(results, fn {service, result} ->
        case result do
          {:ok, :not_supported}        -> []
          {:ok, %{rows_upserted: n}}   -> ["#{service}: #{n} rows synced"]
          {:error, :not_configured}    -> ["#{service}: not configured (skipped)"]
          {:error, reason}             -> ["#{service}: error — #{inspect(reason)}"]
        end
      end)

    flash_msg =
      if Enum.empty?(messages),
        do:   "Nothing to sync.",
        else: Enum.join(messages, " | ")

    conn
    |> put_flash(:info, flash_msg)
    |> redirect(to: dp(conn, "/"))
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.DashboardHTML do
  use LedgrWeb, :html
  embed_templates "dashboard_html/*"

  def status_badge_class(status) do
    case to_string(status) do
      "pending" -> "bg-amber-100 text-amber-800"
      "in_progress" -> "bg-teal-100 text-teal-800"
      "completed" -> "bg-green-100 text-green-800"
      "cancelled" -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end
end
