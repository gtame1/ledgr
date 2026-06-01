defmodule LedgrWeb.Domains.HelloDoctor.WeeklyReportController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.WeeklyReport

  def index(conn, params) do
    {start_date, end_date} = resolve_period(params)
    opts = report_opts(params)
    report = WeeklyReport.generate(start_date, end_date, opts)

    render(conn, :index,
      report: report,
      start_date: start_date,
      end_date: end_date,
      include_settled?: Keyword.fetch!(opts, :include_settled),
      doctor_share: WeeklyReport.doctor_share_per_consultation()
    )
  end

  def download(conn, params) do
    {start_date, end_date} = resolve_period(params)
    opts = report_opts(params)
    csv = WeeklyReport.generate(start_date, end_date, opts) |> WeeklyReport.to_csv()
    filename = "hello-doctor-weekly-#{start_date}-to-#{end_date}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv)
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp resolve_period(params) do
    {default_start, default_end} = WeeklyReport.last_week_range()

    {
      parse_date(params["start_date"]) || default_start,
      parse_date(params["end_date"]) || default_end
    }
  end

  defp report_opts(params) do
    [include_settled: truthy?(params["include_settled"])]
  end

  defp truthy?(v) when v in ["true", "1", "on", "yes"], do: true
  defp truthy?(_), do: false

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.WeeklyReportHTML do
  use LedgrWeb, :html
  embed_templates "weekly_report_html/*"
end
