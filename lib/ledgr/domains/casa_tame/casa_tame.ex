defmodule Ledgr.Domains.CasaTame do
  @moduledoc """
  Casa Tame domain configuration.

  A personal/household finance management app for tracking expenses,
  income, investments, and debts in dual currencies (USD/MXN) with
  unified net worth reporting.
  """

  @behaviour Ledgr.Domain.DomainConfig
  @behaviour Ledgr.Domain.RevenueHandler
  @behaviour Ledgr.Domain.DashboardProvider

  @timezone "America/Mexico_City"

  @doc "Returns today's date in Mexico City timezone."
  def today do
    DateTime.now!(@timezone) |> DateTime.to_date()
  end

  # ── DomainConfig callbacks ──────────────────────────────────────────

  @impl Ledgr.Domain.DomainConfig
  def name, do: "Casa Tame"

  @impl Ledgr.Domain.DomainConfig
  def slug, do: "casa-tame"

  @impl Ledgr.Domain.DomainConfig
  def path_prefix, do: "/app/casa-tame"

  @impl Ledgr.Domain.DomainConfig
  def public_home, do: nil

  @impl Ledgr.Domain.DomainConfig
  def logo, do: "\u{1F3E0}"

  @impl Ledgr.Domain.DomainConfig
  def theme do
    %{
      sidebar_bg: "#1B4332",
      sidebar_text: "#D8F3DC",
      sidebar_hover: "#2D6A4F",
      primary: "#2D6A4F",
      primary_soft: "#D8F3DC",
      accent: "#40916C",
      bg: "#FAFAF5",
      bg_surface: "#FFFFFF",
      border_subtle: "#D8E8D8",
      border_strong: "#B7D1B7",
      text_main: "#1B2A1B",
      text_muted: "#6B7F6B",
      btn_secondary_bg: "#E8F0E8",
      btn_secondary_text: "#1B2A1B",
      btn_secondary_hover: "#D8E8D8",
      btn_primary_hover: "#1B4332",
      shadow_color: "27, 67, 50",
      table_header_bg: "#F0F5F0",
      gradient_start: "#D8F3DC",
      gradient_mid: "#EBF5EB",
      gradient_end: "#FAFAF5",
      logo_emoji: "\u{1F3E0}",
      tab_title: "Casa Tame",
      favicon: "/images/casa-tame-logos/icon.png",
      sidebar_logo: "/images/casa-tame-logos/icon.png",
      sidebar_logo_bg: true,
      card_logo: "/images/casa-tame-logos/icon.png"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def account_codes do
    %{
      # USD accounts
      cash_usd: "1000",
      checking_usd: "1010",
      savings_usd: "1020",
      # MXN accounts
      cash_mxn: "1100",
      checking_mxn: "1110",
      savings_mxn: "1120",
      credit_card_mxn: "1130",
      # Equity
      owners_equity: "3000",
      retained_earnings: "3050",
      owners_drawings: "3100",
      # Revenue
      wages_usd: "4000",
      wages_mxn: "4010",
      freelance_revenue: "4020",
      investment_returns: "4030",
      rental_income: "4040",
      other_income: "4050",
      # Expenses
      housing_expense: "6000",
      food_expense: "6010",
      transport_expense: "6020",
      healthcare_expense: "6030",
      entertainment_expense: "6040",
      personal_expense: "6050",
      financial_expense: "6060",
      pets_expense: "6070",
      travel_expense: "6080",
      subscriptions_expense: "6090",
      other_expense: "6099"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def journal_entry_types do
    [
      {"Personal Expense", "personal_expense"},
      {"Income", "income"},
      {"Investment Deposit", "investment_deposit"},
      {"Investment Withdrawal", "investment_withdrawal"},
      {"Debt Payment", "debt_payment"},
      {"Internal Transfer", "internal_transfer"},
      {"Reconciliation", "reconciliation"}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def menu_items do
    prefix = path_prefix()

    [
      %{group: "Main", items: [
        %{label: "Dashboard",  path: prefix,                    icon: :dashboard},
        %{label: "Expenses",   path: "#{prefix}/expenses",      icon: :expenses},
        %{label: "Income",     path: "#{prefix}/income",        icon: :receipt},
        %{label: "Transfers",  path: "#{prefix}/transfers",     icon: :transfers},
        %{label: "Bills",      path: "#{prefix}/bills",         icon: :documents}
      ]},
      %{group: "Accounts", items: [
        %{label: "Investments", path: "#{prefix}/investment-accounts", icon: :services},
        %{label: "Debts",       path: "#{prefix}/debt-accounts",      icon: :documents}
      ]},
      %{group: "Reports", items: [
        %{label: "Net Worth",          path: "#{prefix}/reports/net-worth",           icon: :reports},
        %{label: "Balance Sheet",      path: "#{prefix}/reports/balance_sheet",       icon: :reports},
        %{label: "Income & Expenses",  path: "#{prefix}/reports/pnl",                icon: :reports},
        %{label: "Monthly Trends",     path: "#{prefix}/reports/monthly-trends",      icon: :reports}
      ]},
      %{group: "Settings", items: [
        %{label: "Reconciliation",        path: "#{prefix}/reconciliation/accounting",  icon: :reconciliation},
        %{label: "All Transactions",      path: "#{prefix}/transactions",               icon: :transactions},
        %{label: "Account Transactions",  path: "#{prefix}/account-transactions",       icon: :transactions}
      ]}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def seed_file, do: nil

  @impl Ledgr.Domain.DomainConfig
  def has_active_dependencies?(_customer_id), do: false

  # ── RevenueHandler callbacks (stubs — personal finance has no business revenue) ──

  @impl Ledgr.Domain.RevenueHandler
  def handle_status_change(_record, _new_status), do: :ok

  @impl Ledgr.Domain.RevenueHandler
  def record_payment(_payment), do: :ok

  @impl Ledgr.Domain.RevenueHandler
  def revenue_breakdown(_start_date, _end_date), do: []

  @impl Ledgr.Domain.RevenueHandler
  def cogs_breakdown(_start_date, _end_date), do: []

  # ── DashboardProvider callbacks ────────────────────────────────────

  @impl Ledgr.Domain.DashboardProvider
  def dashboard_metrics(start_date, end_date) do
    alias Ledgr.Domains.CasaTame.{Expenses, Income, NetWorth, Bills}

    pnl = Ledgr.Core.Accounting.profit_and_loss(start_date, end_date)
    expense_totals = Expenses.total_by_currency(start_date, end_date)
    income_totals = Income.total_by_currency(start_date, end_date)
    net_worth = NetWorth.calculate()
    upcoming_bills = Bills.list_upcoming_bills(14)

    %{
      pnl: pnl,
      expense_totals: expense_totals,
      income_totals: income_totals,
      net_savings_mxn: income_totals.mxn - expense_totals.mxn,
      net_savings_usd: income_totals.usd - expense_totals.usd,
      net_worth: net_worth,
      upcoming_bills: upcoming_bills
    }
  end

  @impl Ledgr.Domain.DashboardProvider
  def unit_economics(_product_id, _start_date, _end_date), do: nil

  @impl Ledgr.Domain.DashboardProvider
  def all_unit_economics(_start_date, _end_date), do: []

  @impl Ledgr.Domain.DashboardProvider
  def product_select_options, do: []

  @impl Ledgr.Domain.DashboardProvider
  def data_date_range do
    Ledgr.Core.Accounting.journal_entry_date_range()
  end

  @impl Ledgr.Domain.DashboardProvider
  def verification_checks, do: %{}

  @impl Ledgr.Domain.DashboardProvider
  def delivered_order_count(_start_date, _end_date), do: 0
end
