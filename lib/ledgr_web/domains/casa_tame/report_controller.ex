defmodule LedgrWeb.Domains.CasaTame.ReportController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.CasaTame.{Expenses, Income, NetWorth}

  def reports_hub(conn, _params) do
    nw = NetWorth.calculate()
    render(conn, :reports_hub, nw: nw)
  end

  def net_worth(conn, _params) do
    nw = NetWorth.calculate()
    render(conn, :net_worth, nw: nw)
  end

  def monthly_trends(conn, _params) do
    today = Ledgr.Domains.CasaTame.today()
    start_date = today |> Date.add(-365) |> Date.beginning_of_month()

    months = build_month_list(start_date, today)

    data =
      Enum.map(months, fn {month_start, month_end} ->
        income = Income.total_by_currency(month_start, month_end)
        expenses = Expenses.total_by_currency(month_start, month_end)

        %{
          label: Calendar.strftime(month_start, "%b %Y"),
          income_mxn: income.mxn,
          expense_mxn: expenses.mxn,
          savings_mxn: income.mxn - expenses.mxn,
          income_usd: income.usd,
          expense_usd: expenses.usd,
          savings_usd: income.usd - expenses.usd
        }
      end)

    chart_data_mxn = %{
      labels: Enum.map(data, fn d -> d.label end),
      datasets: [
        %{label: "Income (MXN)", data: Enum.map(data, fn d -> d.income_mxn / 100 end), backgroundColor: "#059669"},
        %{label: "Expenses (MXN)", data: Enum.map(data, fn d -> d.expense_mxn / 100 end), backgroundColor: "#dc2626"},
        %{label: "Net Savings (MXN)", data: Enum.map(data, fn d -> d.savings_mxn / 100 end), backgroundColor: "#2D6A4F"}
      ]
    }

    render(conn, :monthly_trends, data: data, chart_data_mxn: chart_data_mxn)
  end

  def category_breakdown(conn, params) do
    today = Ledgr.Domains.CasaTame.today()
    month_start = Date.beginning_of_month(today)
    month_end = Date.end_of_month(today)

    start_date = parse_date(params["start_date"]) || month_start
    end_date = parse_date(params["end_date"]) || month_end
    currency = params["currency"] || "MXN"

    expenses = Expenses.list_expenses(currency: currency, date_from: start_date, date_to: end_date)

    # Group by expense account (which IS the category now)
    by_category =
      expenses
      |> Enum.group_by(fn e ->
        if e.expense_account, do: e.expense_account.name, else: "Uncategorized"
      end)
      |> Enum.map(fn {name, items} ->
        %{name: name, total_cents: Enum.reduce(items, 0, &(&1.amount_cents + &2)), count: length(items)}
      end)
      |> Enum.sort_by(& &1.total_cents, :desc)

    chart_data = %{
      labels: Enum.map(by_category, & &1.name),
      datasets: [%{
        data: Enum.map(by_category, fn c -> c.total_cents / 100 end),
        backgroundColor: category_colors(length(by_category))
      }]
    }

    render(conn, :category_breakdown,
      by_category: by_category,
      chart_data: chart_data,
      start_date: start_date,
      end_date: end_date,
      currency: currency
    )
  end

  defp build_month_list(start_date, end_date) do
    Stream.unfold(start_date, fn current ->
      if Date.compare(current, end_date) == :gt do
        nil
      else
        month_end = Date.end_of_month(current)
        next = month_end |> Date.add(1)
        {{current, month_end}, next}
      end
    end)
    |> Enum.to_list()
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp category_colors(n) do
    colors = [
      "#2D6A4F", "#40916C", "#52B788", "#74C69D", "#95D5B2",
      "#B7E4C7", "#D8F3DC", "#1B4332", "#081C15", "#34495E",
      "#7F8C8D", "#BDC3C7", "#E74C3C", "#F39C12", "#3498DB"
    ]
    Enum.take(colors, max(n, 1))
  end
end

defmodule LedgrWeb.Domains.CasaTame.ReportHTML do
  use LedgrWeb, :html

  embed_templates "report_html/*"
end
