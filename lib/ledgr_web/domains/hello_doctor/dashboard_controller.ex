defmodule LedgrWeb.Domains.HelloDoctor.DashboardController do
  use LedgrWeb, :controller

  def index(conn, _params) do
    today = Ledgr.Domains.HelloDoctor.today()
    start_date = Date.beginning_of_month(today)
    end_date = today
    metrics = Ledgr.Domains.HelloDoctor.dashboard_metrics(start_date, end_date)

    conn
    |> assign(:page_title, "Dashboard")
    |> render(:index, Map.to_list(metrics))
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
