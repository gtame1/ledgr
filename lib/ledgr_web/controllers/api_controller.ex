defmodule LedgrWeb.ApiController do
  @moduledoc """
  Core REST API controller for querying shared data (customers, accounting, reports).
  Domain-specific endpoints (products, orders, inventory) live in domain API controllers.
  """
  use LedgrWeb, :controller

  alias Ledgr.Core.{Accounting, Customers}

  # ---------- Customers ----------

  def list_customers(conn, _params) do
    customers = Customers.list_customers()

    json(conn, %{
      data: Enum.map(customers, &serialize_customer/1)
    })
  end

  def show_customer(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)
    json(conn, %{data: serialize_customer(customer)})
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Customer not found"})
  end

  def check_customer_phone(conn, %{"phone" => phone}) do
    case Customers.get_customer_by_phone(phone) do
      nil ->
        json(conn, %{exists: false})

      customer ->
        json(conn, %{exists: true, customer_name: customer.name, customer_id: customer.id})
    end
  end

  # ---------- Accounting ----------

  def list_accounts(conn, _params) do
    accounts = Accounting.list_accounts()

    json(conn, %{
      data: Enum.map(accounts, &serialize_account/1)
    })
  end

  def show_account(conn, %{"id" => id}) do
    account = Accounting.get_account!(id)
    json(conn, %{data: serialize_account(account)})
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Account not found"})
  end

  def list_journal_entries(conn, _params) do
    entries = Accounting.list_journal_entries()

    json(conn, %{
      data: Enum.map(entries, &serialize_journal_entry/1)
    })
  end

  def show_journal_entry(conn, %{"id" => id}) do
    entry = Accounting.get_journal_entry!(id)
    json(conn, %{data: serialize_journal_entry(entry)})
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Journal entry not found"})
  end

  # ---------- Reports ----------

  def balance_sheet(conn, params) do
    as_of_date =
      case params["as_of_date"] do
        nil ->
          today_mx()

        date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            _ -> today_mx()
          end
      end

    report = Accounting.balance_sheet(as_of_date)

    json(conn, %{
      as_of_date: Date.to_iso8601(as_of_date),
      assets: Enum.map(report.assets, &serialize_balance_sheet_line/1),
      liabilities: Enum.map(report.liabilities, &serialize_balance_sheet_line/1),
      equity: Enum.map(report.equity, &serialize_balance_sheet_line/1),
      total_assets_cents: report.total_assets_cents,
      total_liabilities_cents: report.total_liabilities_cents,
      total_equity_cents: report.total_equity_cents,
      net_income_cents: report.net_income_cents,
      liabilities_plus_equity_plus_income_cents: report.liabilities_plus_equity_plus_income_cents,
      balance_diff_cents: report.balance_diff_cents
    })
  end

  def profit_and_loss(conn, params) do
    {start_date, end_date} = parse_date_range(params)

    report = Accounting.profit_and_loss(start_date, end_date)

    json(conn, %{
      start_date: Date.to_iso8601(start_date),
      end_date: Date.to_iso8601(end_date),
      total_revenue_cents: report.total_revenue_cents,
      total_cogs_cents: report.total_cogs_cents,
      gross_profit_cents: report.gross_profit_cents,
      total_opex_cents: report.total_opex_cents,
      operating_income_cents: report.operating_income_cents,
      net_income_cents: report.net_income_cents,
      gross_margin_percent: report.gross_margin_percent,
      operating_margin_percent: report.operating_margin_percent,
      net_margin_percent: report.net_margin_percent,
      revenue_accounts: Enum.map(report.revenue_accounts, &serialize_pnl_account/1),
      cogs_accounts: Enum.map(report.cogs_accounts, &serialize_pnl_account/1),
      operating_expense_accounts:
        Enum.map(report.operating_expense_accounts, &serialize_pnl_account/1)
    })
  end

  # ---------- Serializers ----------

  defp serialize_customer(customer) do
    %{
      id: customer.id,
      name: customer.name,
      email: customer.email,
      phone: customer.phone,
      delivery_address: customer.delivery_address,
      inserted_at: customer.inserted_at,
      updated_at: customer.updated_at
    }
  end

  defp serialize_account(account) do
    %{
      id: account.id,
      code: account.code,
      name: account.name,
      type: account.type,
      normal_balance: account.normal_balance,
      is_cash: account.is_cash
    }
  end

  defp serialize_journal_entry(entry) do
    %{
      id: entry.id,
      date: entry.date,
      entry_type: entry.entry_type,
      reference: entry.reference,
      description: entry.description,
      total_cents: Map.get(entry, :total_cents),
      journal_lines: Enum.map(entry.journal_lines || [], &serialize_journal_line/1),
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end

  defp serialize_journal_line(line) do
    %{
      id: line.id,
      account: line.account && serialize_account(line.account),
      debit_cents: line.debit_cents,
      credit_cents: line.credit_cents,
      description: line.description
    }
  end

  defp serialize_balance_sheet_line(line) do
    %{
      account: serialize_account(line.account),
      amount_cents: line.amount_cents
    }
  end

  defp serialize_pnl_account(account) do
    %{
      code: account.code,
      name: account.name,
      net_cents: account.net_cents
    }
  end

  # ---------- Helpers ----------

  defp parse_date_range(params) do
    today = today_mx()

    start_date =
      case params["start_date"] do
        nil ->
          Date.beginning_of_month(today)

        date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            _ -> Date.beginning_of_month(today)
          end
      end

    end_date =
      case params["end_date"] do
        nil ->
          today

        date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            _ -> today
          end
      end

    {start_date, end_date}
  end
end
