defmodule LedgrWeb.Domains.EscuelaDeDinero.DashboardController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.EscuelaDeDinero
  alias Ledgr.Domains.EscuelaDeDinero.DashboardMetrics

  @periods [
    {"last_7_days", "Últimos 7 días", 6},
    {"last_30_days", "Últimos 30 días", 29},
    {"last_90_days", "Últimos 90 días", 89}
  ]

  @default_period "last_30_days"

  def index(conn, params) do
    period = resolve_period(params["period"])
    {start_date, end_date} = period_range(period)

    metrics = DashboardMetrics.all(start_date, end_date)

    render(conn, :index,
      metrics: metrics,
      funnel_rows: DashboardMetrics.diagnostico_funnel_rows(metrics.diagnostico_funnel),
      period: period,
      periods: Enum.map(@periods, fn {value, label, _} -> {value, label} end),
      start_date: start_date,
      end_date: end_date
    )
  end

  # Deliberately local rather than reaching into ReportController — its
  # `resolve_period/1` is private, and this domain doesn't route it at all.
  defp resolve_period(nil), do: @default_period

  defp resolve_period(value) do
    if Enum.any?(@periods, fn {v, _, _} -> v == value end), do: value, else: @default_period
  end

  defp period_range(period) do
    {_, _, days_back} = Enum.find(@periods, fn {v, _, _} -> v == period end)
    today = EscuelaDeDinero.today()
    {Date.add(today, -days_back), today}
  end
end

defmodule LedgrWeb.Domains.EscuelaDeDinero.DashboardHTML do
  use LedgrWeb, :html
  use LedgrWeb.Domains.EscuelaDeDinero.StateLabels
  embed_templates "dashboard_html/*"
end
