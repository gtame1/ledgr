defmodule LedgrWeb.Domains.HelloDoctor.MonthlyReportController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.MonthlyReport

  def index(conn, params) do
    {start_date, end_date} = resolve_period(params)
    opts = report_opts(params)
    report = MonthlyReport.generate(start_date, end_date, opts)

    # Default view (no date params) = all outstanding balances, any date.
    all_outstanding? = is_nil(start_date)
    nav_date = start_date || Ledgr.Domains.HelloDoctor.today()

    render(conn, :index,
      report: report,
      start_date: start_date,
      end_date: end_date,
      all_outstanding?: all_outstanding?,
      month_key: if(all_outstanding?, do: nil, else: month_key(start_date)),
      prev_month: month_key(MonthlyReport.shift_month(nav_date, -1)),
      next_month: month_key(MonthlyReport.shift_month(nav_date, 1)),
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

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="hello-doctor-payouts-#{period_slug(start_date, end_date)}.csv")
    )
    |> send_resp(200, csv)
  end

  def download_xlsx(conn, params) do
    {start_date, end_date} = resolve_period(params)
    opts = report_opts(params)
    xlsx = MonthlyReport.generate(start_date, end_date, opts) |> MonthlyReport.to_xlsx()

    conn
    |> put_resp_content_type("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="hello-doctor-payouts-#{period_slug(start_date, end_date)}.xlsx")
    )
    |> send_resp(200, xlsx)
  end

  # ── Helpers ─────────────────────────────────────────────────────

  # Resolution order:
  #   1. explicit start_date + end_date (any range, possibly multi-month)
  #   2. ?month=YYYY-MM
  #   3. default = ALL OUTSTANDING (no date bound) — every unpaid balance.
  defp resolve_period(params) do
    explicit_start = parse_date(params["start_date"])
    explicit_end = parse_date(params["end_date"])

    cond do
      explicit_start && explicit_end ->
        {explicit_start, explicit_end}

      month_range = MonthlyReport.parse_month(params["month"]) ->
        month_range

      true ->
        {nil, nil}
    end
  end

  defp period_slug(nil, nil), do: "all-outstanding-#{Ledgr.Domains.HelloDoctor.today()}"
  defp period_slug(s, e), do: "#{s}-to-#{e}"

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
  def csv_href(prefix, assigns), do: "#{prefix}/reports/monthly/download?#{report_query(assigns)}"

  @doc "Same, for the two-sheet .xlsx download (Resumen + Detalle)."
  def xlsx_href(prefix, assigns), do: "#{prefix}/reports/monthly/xlsx?#{report_query(assigns)}"

  # Preserve the current scope (month, if any) + settled toggle. A nil
  # month_key (all-outstanding view) drops the param so the download
  # matches what's on screen.
  defp report_query(%{month_key: month_key, include_settled?: included?}) do
    [{"month", month_key}, {"include_settled", if(included?, do: "true", else: nil)}]
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> URI.encode_query()
  end
end
