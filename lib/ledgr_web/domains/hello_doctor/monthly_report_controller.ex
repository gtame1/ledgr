defmodule LedgrWeb.Domains.HelloDoctor.MonthlyReportController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.MonthlyReport
  alias Ledgr.Domains.HelloDoctor.MonthlyPayoutRun

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

  # Elixlsx builds the whole workbook in memory — the sheet data, the generated
  # XML and the zip binary are all live at once — so unlike the CSV exports this
  # one cannot stream. Bound the input instead. The report is a monthly payout
  # run; a quarter is already well past the use case.
  @max_xlsx_days 100

  def download_xlsx(conn, params) do
    {start_date, end_date} = resolve_period(params)
    opts = report_opts(params)

    if Date.diff(end_date, start_date) > @max_xlsx_days do
      conn
      |> put_flash(
        :error,
        "That range is too long for Excel (max #{@max_xlsx_days} days). " <>
          "Use the CSV download, which has no limit."
      )
      |> redirect(to: dp(conn, "/reports/monthly"))
    else
      do_download_xlsx(conn, start_date, end_date, opts)
    end
  end

  defp do_download_xlsx(conn, start_date, end_date, opts) do
    xlsx = MonthlyReport.generate(start_date, end_date, opts) |> MonthlyReport.to_xlsx()

    conn
    |> put_resp_content_type("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="hello-doctor-payouts-#{period_slug(start_date, end_date)}.xlsx")
    )
    |> send_resp(200, xlsx)
  end

  # ── Bulk "mark month as paid" ───────────────────────────────────

  @doc """
  Preview page: shows exactly what recording payouts for the period would do
  (per doctor: consultations, comp accruals, gross share, ISR withheld, net
  cash) with a confirm button. Writes nothing.
  """
  def mark_paid_preview(conn, params) do
    {start_date, end_date} = resolve_period(params)
    plan = MonthlyPayoutRun.plan(start_date, end_date)

    render(conn, :mark_paid,
      plan: plan,
      start_date: start_date,
      end_date: end_date,
      month_key: if(is_nil(start_date), do: nil, else: month_key(start_date)),
      period_label: period_label(start_date, end_date),
      payout_date: Ledgr.Domains.HelloDoctor.today()
    )
  end

  @doc "Executes the bulk payout, then redirects back to the report."
  def mark_paid(conn, params) do
    {start_date, end_date} = resolve_period(params)
    payout_date = parse_date(params["payout_date"]) || Ledgr.Domains.HelloDoctor.today()
    label = period_label(start_date, end_date)

    summary =
      MonthlyPayoutRun.execute(start_date, end_date, payout_date, period_label: label)

    conn
    |> put_flash(flash_level(summary), mark_paid_flash(summary, label))
    |> redirect(to: dp(conn, "/reports/monthly?#{report_query(start_date, end_date)}"))
  end

  defp flash_level(%{doctors_paid: 0, doctors_failed: 0}), do: :info
  defp flash_level(%{doctors_failed: n}) when n > 0, do: :error
  defp flash_level(_), do: :info

  defp mark_paid_flash(%{doctors_paid: 0, doctors_failed: 0}, label),
    do: "Nothing owed for #{label} — no payouts recorded."

  defp mark_paid_flash(s, label) do
    base =
      "Recorded payouts for #{s.doctors_paid} doctor(s) across #{s.consultations_paid} " <>
        "consultation(s) for #{label}: $#{fmt(s.total_cash)} MXN net cash, " <>
        "$#{fmt(s.total_isr)} ISR withheld"

    base = if s.accruals_posted > 0, do: "#{base}, #{s.accruals_posted} comp accrual(s) posted", else: base

    if s.doctors_failed > 0 do
      names = s.failures |> Enum.map(&elem(&1, 0)) |> Enum.join(", ")
      "#{base}. #{s.doctors_failed} doctor(s) FAILED — check logs: #{names}."
    else
      "#{base}."
    end
  end

  defp fmt(n), do: :erlang.float_to_binary(n + 0.0, decimals: 2)

  # Query string that re-scopes the report to the same period on redirect.
  defp report_query(nil, nil), do: ""
  defp report_query(s, e), do: URI.encode_query(%{"start_date" => to_string(s), "end_date" => to_string(e)})

  defp period_label(nil, nil), do: "all outstanding"

  defp period_label(s, e) do
    if Date.beginning_of_month(s) == s and Date.end_of_month(s) == e do
      Calendar.strftime(s, "%B %Y")
    else
      "#{s} to #{e}"
    end
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

  @doc "Link to the bulk 'mark as paid' preview, preserving the current period."
  def mark_paid_href(prefix, assigns) do
    query =
      cond do
        assigns.month_key ->
          URI.encode_query(%{"month" => assigns.month_key})

        assigns.start_date && assigns.end_date ->
          URI.encode_query(%{
            "start_date" => to_string(assigns.start_date),
            "end_date" => to_string(assigns.end_date)
          })

        true ->
          ""
      end

    "#{prefix}/reports/monthly/mark-paid" <> if(query == "", do: "", else: "?#{query}")
  end

  # Preserve the current scope (month, if any) + settled toggle. A nil
  # month_key (all-outstanding view) drops the param so the download
  # matches what's on screen.
  defp report_query(%{month_key: month_key, include_settled?: included?}) do
    [{"month", month_key}, {"include_settled", if(included?, do: "true", else: nil)}]
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> URI.encode_query()
  end
end
