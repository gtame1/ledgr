defmodule LedgrWeb.Domains.HelloDoctor.MonthlyReportController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.MonthlyReport

  def index(conn, params) do
    {start_date, end_date} = resolve_period(params)
    opts = report_opts(params)
    report = MonthlyReport.generate(start_date, end_date, opts)

    render(conn, :index,
      report: report,
      start_date: start_date,
      end_date: end_date,
      month_key: month_key(start_date),
      prev_month: month_key(MonthlyReport.shift_month(start_date, -1)),
      next_month: month_key(MonthlyReport.shift_month(start_date, 1)),
      this_month: month_key(Ledgr.Domains.HelloDoctor.today()),
      last_month: month_key(MonthlyReport.shift_month(Ledgr.Domains.HelloDoctor.today(), -1)),
      month_options: MonthlyReport.month_options(12),
      include_settled?: Keyword.fetch!(opts, :include_settled),
      doctor_share: MonthlyReport.doctor_share_per_consultation()
    )
  end

  def download(conn, params) do
    {start_date, end_date} = resolve_period(params)
    opts = report_opts(params)
    csv = MonthlyReport.generate(start_date, end_date, opts) |> MonthlyReport.to_csv()
    filename = "hello-doctor-monthly-#{start_date}-to-#{end_date}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv)
  end

  # ── Helpers ─────────────────────────────────────────────────────

  # Resolution order:
  #   1. explicit start_date + end_date (any range, possibly multi-month)
  #   2. ?month=YYYY-MM
  #   3. default = previous calendar month
  defp resolve_period(params) do
    explicit_start = parse_date(params["start_date"])
    explicit_end = parse_date(params["end_date"])

    cond do
      explicit_start && explicit_end ->
        {explicit_start, explicit_end}

      month_range = MonthlyReport.parse_month(params["month"]) ->
        month_range

      true ->
        MonthlyReport.last_month_range()
    end
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

  defp month_key(date), do: Calendar.strftime(date, "%Y-%m")
end

defmodule LedgrWeb.Domains.HelloDoctor.MonthlyReportHTML do
  use LedgrWeb, :html
  embed_templates "monthly_report_html/*"

  @doc "Pretty month label, e.g. 'May 2026'."
  def month_label(date), do: Calendar.strftime(date, "%B %Y")

  @doc """
  Builds the CSV download URL preserving the currently displayed
  filter state.
  """
  def csv_href(prefix, %{month_key: month_key, include_settled?: included?}) do
    query =
      [{"month", month_key}, {"include_settled", if(included?, do: "true", else: nil)}]
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> URI.encode_query()

    "#{prefix}/reports/monthly/download?#{query}"
  end
end
