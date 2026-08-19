defmodule LedgrWeb.Domains.AumentaMiPension.DashboardController do
  use LedgrWeb, :controller

  alias Ledgr.Core.Settings
  alias Ledgr.Domains.AumentaMiPension

  @doc """
  Aumenta Mi Pensión's operational dashboard.

  Moved off the shared `ReportController` so this domain stops routing the
  accounting surface, matching Escuela de Dinero and Hello Doctor. Unlike HD
  there are no period-over-period delta chips, so there is no comparison
  window to compute.

  `resolve_period/1` is deliberately duplicated rather than shared — the
  original was private to `ReportController`, and each domain's period
  semantics are diverging.
  """
  def index(conn, params) do
    # AMP defaults to the last 30 days rather than the calendar month.
    params =
      if not Map.has_key?(params, "period") and not Map.has_key?(params, "start_date") and
           not Map.has_key?(params, "all_dates") do
        Map.put(params, "period", "last_30_days")
      else
        params
      end

    {start_date, end_date} = resolve_period(params)
    {earliest_date, latest_date} = AumentaMiPension.data_date_range()

    render(conn, :index,
      metrics: AumentaMiPension.dashboard_metrics(start_date, end_date),
      comparison: nil,
      start_date: start_date,
      end_date: end_date,
      earliest_date: earliest_date,
      latest_date: latest_date,
      current_period: params["period"],
      usd_mxn_rate: Settings.get_usd_mxn_rate()
    )
  end

  defp resolve_period(%{"period" => "last_7_days"}) do
    today = today_mx()
    {Date.add(today, -6), today}
  end

  defp resolve_period(%{"period" => "last_30_days"}) do
    today = today_mx()
    {Date.add(today, -29), today}
  end

  defp resolve_period(%{"period" => "this_month"}) do
    today = today_mx()
    {%Date{today | day: 1}, today}
  end

  defp resolve_period(%{"period" => "last_90_days"}) do
    today = today_mx()
    {Date.add(today, -89), today}
  end

  defp resolve_period(%{"all_dates" => "true"}) do
    case AumentaMiPension.data_date_range() do
      {nil, nil} ->
        today = today_mx()
        {%Date{today | day: 1}, today}

      {earliest, latest} ->
        {%Date{earliest | day: 1}, Enum.max([latest, today_mx()], Date)}
    end
  end

  defp resolve_period(%{"period" => "all_time"}), do: resolve_period(%{"all_dates" => "true"})

  defp resolve_period(%{"start_date" => s, "end_date" => e}) when s != "" and e != "" do
    {:ok, start_date} = Date.from_iso8601(s)
    {:ok, end_date} = Date.from_iso8601(e)
    {start_date, end_date}
  end

  defp resolve_period(_params) do
    today = today_mx()
    {%Date{today | day: 1}, today}
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.DashboardHTML do
  use LedgrWeb, :html

  import LedgrWeb.CoreComponents

  embed_templates "dashboard_html/*"
end
