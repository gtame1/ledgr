defmodule LedgrWeb.ReportController do
  use LedgrWeb, :controller

  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Reporting
  alias Ledgr.Core.Settings
  alias Ledgr.Domain

  def mr_munch_me_more(conn, _params) do
    render(conn, :mr_munch_me_more)
  end

  def dashboard(conn, params) do
    domain = Domain.current()

    # HelloDoctor / AumentaMiPension default to last 30 days; other domains keep "this month" default
    params =
      if domain in [Ledgr.Domains.HelloDoctor, Ledgr.Domains.AumentaMiPension] and
           not Map.has_key?(params, "period") and
           not Map.has_key?(params, "start_date") and not Map.has_key?(params, "all_dates") do
        Map.put(params, "period", "last_30_days")
      else
        params
      end

    {start_date, end_date} = resolve_period(params)
    {earliest_date, latest_date} = domain.data_date_range()

    metrics = domain.dashboard_metrics(start_date, end_date)

    # Prior equal-length window, immediately preceding the current one, for
    # the HelloDoctor dashboard's period-over-period delta chips. Skipped for
    # "all time" (no meaningful prior period) and for other domains.
    comparison =
      if domain == Ledgr.Domains.HelloDoctor and params["period"] != "all_time" and
           params["all_dates"] != "true" do
        len = Date.diff(end_date, start_date) + 1
        prior_end = Date.add(start_date, -1)
        prior_start = Date.add(prior_end, -(len - 1))

        Ledgr.Domains.HelloDoctor.DashboardMetrics.period_summary(prior_start, prior_end)
        |> Map.merge(%{start_date: prior_start, end_date: prior_end})
      end

    template =
      cond do
        domain == Ledgr.Domains.VolumeStudio -> :volume_studio_dashboard
        domain == Ledgr.Domains.LedgrHQ -> :ledgr_hq_dashboard
        domain == Ledgr.Domains.CasaTame -> :casa_tame_dashboard
        domain == Ledgr.Domains.MrMunchMe -> :mr_munch_me_dashboard
        domain == Ledgr.Domains.HelloDoctor -> :hello_doctor_dashboard
        domain == Ledgr.Domains.AumentaMiPension -> :aumenta_mi_pension_dashboard
        true -> :dashboard
      end

    render(conn, template,
      metrics: metrics,
      comparison: comparison,
      start_date: start_date,
      end_date: end_date,
      earliest_date: earliest_date,
      latest_date: latest_date,
      current_period: params["period"],
      usd_mxn_rate: Settings.get_usd_mxn_rate()
    )
  end

  # P&L for a period (default: current month)
  def pnl(conn, params) do
    domain = Domain.current()
    {start_date, end_date} = resolve_period(params)
    {earliest_date, latest_date} = domain.data_date_range()

    summary = Accounting.profit_and_loss(start_date, end_date)
    # `months` query param picks the trailing-window size for templates that
    # render a multi-month spreadsheet (currently HD). 3/6/12; default 6.
    # `profit_and_loss_monthly/1` argument is "months back from current",
    # so N total months = call with N - 1.
    months_window =
      case params["months"] do
        "3" -> 3
        "6" -> 6
        "12" -> 12
        _ -> 6
      end

    monthly = Accounting.profit_and_loss_monthly(months_window - 1)

    template =
      cond do
        domain == Ledgr.Domains.CasaTame -> :casa_tame_pnl
        domain == Ledgr.Domains.MrMunchMe -> :mr_munch_me_pnl
        domain == Ledgr.Domains.HelloDoctor -> :hello_doctor_pnl
        domain == Ledgr.Domains.AumentaMiPension -> :aumenta_mi_pension_pnl
        true -> :pnl
      end

    # Casa Tame needs expense/income totals by currency for the split P&L
    extra_assigns =
      if domain == Ledgr.Domains.CasaTame do
        [
          expense_totals: Ledgr.Domains.CasaTame.Expenses.total_by_currency(start_date, end_date),
          expense_by_account:
            Ledgr.Domains.CasaTame.Expenses.totals_by_account_and_currency(start_date, end_date),
          income_by_category:
            Ledgr.Domains.CasaTame.Income.totals_by_category_and_currency(start_date, end_date),
          income_totals: Ledgr.Domains.CasaTame.Income.total_by_currency(start_date, end_date)
        ]
      else
        []
      end

    render(
      conn,
      template,
      [
        summary: summary,
        monthly: monthly,
        months_window: months_window,
        start_date: start_date,
        end_date: end_date,
        earliest_date: earliest_date,
        latest_date: latest_date
      ] ++ extra_assigns
    )
  end

  # Balance sheet as of a given date (default: today)
  def balance_sheet(conn, params) do
    as_of =
      case Map.get(params, "as_of") do
        nil -> today_mx()
        "" -> today_mx()
        date_str -> Date.from_iso8601!(date_str)
      end

    bs = Accounting.balance_sheet(as_of)

    template =
      cond do
        Domain.current() == Ledgr.Domains.CasaTame -> :casa_tame_balance_sheet
        Domain.current() == Ledgr.Domains.MrMunchMe -> :mr_munch_me_balance_sheet
        Domain.current() == Ledgr.Domains.HelloDoctor -> :hello_doctor_balance_sheet
        Domain.current() == Ledgr.Domains.AumentaMiPension -> :aumenta_mi_pension_balance_sheet
        true -> :balance_sheet
      end

    render(conn, template,
      balance_sheet: bs,
      as_of: as_of
    )
  end

  # Year-end close action
  def year_end_close(conn, params) do
    close_date =
      case Map.get(params, "close_date") do
        nil -> Date.new!(today_mx().year - 1, 12, 31)
        "" -> Date.new!(today_mx().year - 1, 12, 31)
        date_str -> Date.from_iso8601!(date_str)
      end

    case Accounting.close_year_end(close_date) do
      {:ok, :nothing_to_close} ->
        conn
        |> put_flash(:info, "No income or drawings to close for #{close_date}.")
        |> redirect(to: dp(conn, "/reports/balance_sheet"))

      {:ok, _entry} ->
        conn
        |> put_flash(:info, "Year-end close completed successfully for #{close_date}.")
        |> redirect(to: dp(conn, "/reports/balance_sheet"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Year-end close failed: #{reason}")
        |> redirect(to: dp(conn, "/reports/balance_sheet"))
    end
  end

  def unit_economics(conn, params) do
    domain = Domain.current()
    {start_date, end_date} = resolve_period(params)

    # Get product_id from params, default to first product if not provided
    product_options = domain.product_select_options()

    product_id =
      case Map.get(params, "product_id") do
        nil ->
          # Get first active product
          case product_options do
            [{_label, id} | _] -> id
            [] -> nil
          end

        "" ->
          nil

        id_str when is_binary(id_str) ->
          case Integer.parse(id_str) do
            {id, _} -> id
            :error -> nil
          end

        id when is_integer(id) ->
          id

        _ ->
          nil
      end

    unit_economics_data =
      if product_id do
        try do
          domain.unit_economics(product_id, start_date, end_date)
        rescue
          Ecto.NoResultsError ->
            # Product doesn't exist - return nil
            nil
        end
      else
        nil
      end

    {earliest_date, latest_date} = domain.data_date_range()

    render(conn, :unit_economics,
      unit_economics: unit_economics_data,
      product_options: product_options,
      selected_product_id: product_id,
      start_date: start_date,
      end_date: end_date,
      earliest_date: earliest_date,
      latest_date: latest_date
    )
  end

  def cash_flow(conn, params) do
    domain = Domain.current()
    {start_date, end_date} = resolve_period(params)
    {earliest_date, latest_date} = domain.data_date_range()

    cash_flow_data = Reporting.cash_flow(start_date, end_date)

    template =
      cond do
        domain == Ledgr.Domains.CasaTame -> :casa_tame_cash_flow
        domain == Ledgr.Domains.MrMunchMe -> :mr_munch_me_cash_flow
        true -> :cash_flow
      end

    render(conn, template,
      cash_flow: cash_flow_data,
      start_date: start_date,
      end_date: end_date,
      earliest_date: earliest_date,
      latest_date: latest_date
    )
  end

  def unit_economics_list(conn, params) do
    domain = Domain.current()
    {start_date, end_date} = resolve_period(params)
    {earliest_date, latest_date} = domain.data_date_range()

    all_unit_economics = domain.all_unit_economics(start_date, end_date)

    # Calculate totals across all products
    totals = calculate_totals(all_unit_economics)

    render(conn, :unit_economics_list,
      all_unit_economics: all_unit_economics,
      totals: totals,
      start_date: start_date,
      end_date: end_date,
      earliest_date: earliest_date,
      latest_date: latest_date
    )
  end

  defp calculate_totals(all_unit_economics) do
    Enum.reduce(
      all_unit_economics,
      %{
        units_sold: 0,
        revenue_cents: 0,
        cogs_cents: 0,
        gross_margin_cents: 0,
        net_profit_cents: 0
      },
      fn ue, acc ->
        %{
          units_sold: acc.units_sold + ue.units_sold,
          revenue_cents: acc.revenue_cents + ue.revenue_cents,
          cogs_cents: acc.cogs_cents + ue.cogs_cents,
          gross_margin_cents: acc.gross_margin_cents + ue.gross_margin_cents,
          net_profit_cents: acc.net_profit_cents + ue.net_profit_cents
        }
      end
    )
    |> then(fn totals ->
      gross_margin_percent =
        if totals.revenue_cents > 0 do
          Float.round(totals.gross_margin_cents / totals.revenue_cents * 100, 2)
        else
          0.0
        end

      net_margin_percent =
        if totals.revenue_cents > 0 do
          Float.round(totals.net_profit_cents / totals.revenue_cents * 100, 2)
        else
          0.0
        end

      # Calculate per-unit averages
      revenue_per_unit_cents =
        if totals.units_sold > 0, do: div(totals.revenue_cents, totals.units_sold), else: 0

      cogs_per_unit_cents =
        if totals.units_sold > 0, do: div(totals.cogs_cents, totals.units_sold), else: 0

      gross_margin_per_unit_cents =
        if totals.units_sold > 0, do: div(totals.gross_margin_cents, totals.units_sold), else: 0

      totals
      |> Map.put(:gross_margin_percent, gross_margin_percent)
      |> Map.put(:net_margin_percent, net_margin_percent)
      |> Map.put(:revenue_per_unit_cents, revenue_per_unit_cents)
      |> Map.put(:cogs_per_unit_cents, cogs_per_unit_cents)
      |> Map.put(:gross_margin_per_unit_cents, gross_margin_per_unit_cents)
    end)
  end

  def financial_analysis(conn, params) do
    domain = Domain.current()
    {start_date, end_date} = resolve_period(params)
    {earliest_date, latest_date} = domain.data_date_range()

    # Gather domain-specific enrichment data
    inventory_value_cents = get_inventory_value()
    delivered_order_count = domain.delivered_order_count(start_date, end_date)

    analysis =
      Reporting.financial_analysis(start_date, end_date,
        inventory_value_cents: inventory_value_cents,
        delivered_order_count: delivered_order_count
      )

    template =
      if Domain.current() == Ledgr.Domains.MrMunchMe,
        do: :mr_munch_me_financial_analysis,
        else: :financial_analysis

    render(conn, template,
      analysis: analysis,
      start_date: start_date,
      end_date: end_date,
      earliest_date: earliest_date,
      latest_date: latest_date
    )
  end

  # Helpers

  defp get_inventory_value do
    try do
      Ledgr.Domains.MrMunchMe.Inventory.total_inventory_value_cents()
    rescue
      _ -> nil
    end
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
    start_of_month = %Date{today | day: 1}
    {start_of_month, today}
  end

  defp resolve_period(%{"period" => "last_90_days"}) do
    today = today_mx()
    {Date.add(today, -89), today}
  end

  defp resolve_period(%{"all_dates" => "true"}) do
    domain = Domain.current()
    {earliest, latest} = domain.data_date_range()

    case {earliest, latest} do
      {nil, nil} ->
        # No data at all, default to current month
        today = today_mx()
        start_of_month = %Date{today | day: 1}
        {start_of_month, today}

      {earliest, latest} ->
        # Start from the 1st of the earliest month
        start_date = %Date{earliest | day: 1}
        end_date = Enum.max([latest, today_mx()], Date)
        {start_date, end_date}
    end
  end

  # Alias for "all_time" period
  defp resolve_period(%{"period" => "all_time"}), do: resolve_period(%{"all_dates" => "true"})

  defp resolve_period(%{"start_date" => s, "end_date" => e}) when s != "" and e != "" do
    {:ok, start_date} = Date.from_iso8601(s)
    {:ok, end_date} = Date.from_iso8601(e)
    {start_date, end_date}
  end

  defp resolve_period(_params) do
    today = today_mx()
    start_of_month = %Date{today | day: 1}
    {start_of_month, today}
  end

  def ap_summary(conn, _params) do
    ap_accounts = Accounting.get_ap_accounts_with_balances()

    ap_accounts_with_detail =
      Enum.map(ap_accounts, fn entry ->
        all_lines = Accounting.list_journal_lines_by_account(entry.account.id)

        detail =
          if entry.account.code == "2000" do
            payee_groups =
              all_lines
              |> Enum.group_by(fn line -> line.journal_entry.payee || "(No payee)" end)
              |> Enum.map(fn {payee, lines} ->
                balance =
                  Enum.reduce(lines, 0, fn l, acc -> acc + l.credit_cents - l.debit_cents end)

                %{payee: payee, balance_cents: balance, lines: Enum.take(lines, 10)}
              end)
              |> Enum.sort_by(&(-&1.balance_cents))

            {:general, payee_groups}
          else
            {:named, Enum.take(all_lines, 10)}
          end

        Map.put(entry, :detail, detail)
      end)

    total_ap_cents = Enum.sum(Enum.map(ap_accounts_with_detail, & &1.balance_cents))

    render(conn, :ap_summary,
      ap_accounts: ap_accounts_with_detail,
      total_ap_cents: total_ap_cents
    )
  end
end

defmodule LedgrWeb.ReportHTML do
  use LedgrWeb, :html

  import LedgrWeb.CoreComponents

  embed_templates "report_html/*"

  def status_dot_color("active"), do: "#16a34a"
  def status_dot_color("trial"), do: "#d97706"
  def status_dot_color("paused"), do: "#9ca3af"
  def status_dot_color("churned"), do: "#ef4444"
  def status_dot_color(_), do: "#9ca3af"

  @doc """
  Small period-over-period delta pill for the HelloDoctor dashboard KPIs.

  `current` / `prior` are the same scalar measured in this period and the
  prior equal-length window. `:mode` is `:pct` (relative % change, for
  counts) or `:point` (absolute point change, for rates already in %).
  Renders nothing when `prior` is nil (comparison disabled, e.g. all-time).
  """
  attr :current, :any, default: nil
  attr :prior, :any, default: nil
  attr :mode, :atom, default: :pct

  def hd_delta_chip(assigns) do
    assigns = assign(assigns, :delta, hd_delta(assigns.current, assigns.prior, assigns.mode))

    ~H"""
    <span
      :if={@delta}
      class="inline-flex items-center gap-0.5"
      style={"font-size:0.7rem;font-weight:700;padding:1px 7px;border-radius:20px;#{hd_chip_style(elem(@delta, 0))}"}
      title="vs. previous period of equal length"
    >
      <span style="font-size:0.6rem;line-height:1;">{hd_chip_arrow(elem(@delta, 0))}</span>
      {elem(@delta, 1)}
    </span>
    """
  end

  defp hd_delta(cur, prior, _mode) when is_nil(cur) or is_nil(prior), do: nil

  defp hd_delta(cur, prior, :point) when is_number(cur) and is_number(prior) do
    d = Float.round((cur - prior) * 1.0, 1)

    cond do
      d > 0.05 -> {:up, "+" <> :erlang.float_to_binary(d, decimals: 1) <> "pt"}
      d < -0.05 -> {:down, :erlang.float_to_binary(d, decimals: 1) <> "pt"}
      true -> {:flat, "0pt"}
    end
  end

  defp hd_delta(cur, prior, :pct) when is_number(cur) and is_number(prior) do
    cond do
      prior == 0 and cur == 0 -> {:flat, "0%"}
      prior == 0 -> {:up, "new"}
      true -> hd_pct_chip((cur - prior) / prior * 100)
    end
  end

  defp hd_delta(_, _, _), do: nil

  defp hd_pct_chip(change) do
    rounded = round(change)

    cond do
      rounded > 0 -> {:up, "+#{rounded}%"}
      rounded < 0 -> {:down, "#{rounded}%"}
      true -> {:flat, "0%"}
    end
  end

  defp hd_chip_style(:up), do: "background:#d1fae5;color:#047857;"
  defp hd_chip_style(:down), do: "background:#fee2e2;color:#b91c1c;"
  defp hd_chip_style(:flat), do: "background:#f1f5f9;color:#64748b;"

  defp hd_chip_arrow(:up), do: "▲"
  defp hd_chip_arrow(:down), do: "▼"
  defp hd_chip_arrow(:flat), do: "—"
end
