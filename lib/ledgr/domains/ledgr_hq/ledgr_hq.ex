defmodule Ledgr.Domains.LedgrHQ do
  @moduledoc """
  Ledgr HQ domain configuration.

  Tracks the ledgr SaaS business itself: client accounts, subscription plans,
  recurring infrastructure costs, and key metrics (MRR, ARR, profit margin).

  Revenue streams:
  - Subscription Revenue: monthly fees from clients using ledgr-built apps

  Costs tracked:
  - Cloud & Hosting: Fly.io, Railway, AWS, etc.
  - Domains & DNS: domain registration, DNS management
  - SaaS & Tools: third-party tools (Stripe, email, etc.)
  """

  @behaviour Ledgr.Domain.DomainConfig
  @behaviour Ledgr.Domain.RevenueHandler
  @behaviour Ledgr.Domain.DashboardProvider

  # ── DomainConfig callbacks ──────────────────────────────────────────

  @impl Ledgr.Domain.DomainConfig
  def name, do: "Ledgr HQ"

  @impl Ledgr.Domain.DomainConfig
  def slug, do: "ledgr"

  @impl Ledgr.Domain.DomainConfig
  def path_prefix, do: "/app/ledgr"

  @impl Ledgr.Domain.DomainConfig
  def public_home, do: nil

  @impl Ledgr.Domain.DomainConfig
  def logo, do: "📊"

  @impl Ledgr.Domain.DomainConfig
  def theme do
    %{
      sidebar_bg: "#12213D",
      sidebar_text: "#F0F4FA",
      sidebar_hover: "#1E3460",
      primary: "#1E478C",
      primary_soft: "#E8EFF8",
      accent: "#3B7CC9",
      bg: "#F8FAFC",
      bg_surface: "#F0F4F9",
      border_subtle: "#DDE5F0",
      border_strong: "#BEC9DC",
      text_main: "#1A2744",
      text_muted: "#5A6E8A",
      btn_secondary_bg: "#DDE5F0",
      btn_secondary_text: "#1A2744",
      btn_secondary_hover: "#BEC9DC",
      btn_primary_hover: "#163870",
      shadow_color: "26, 39, 68",
      table_header_bg: "#F0F4F9",
      gradient_start: "#D6E4F7",
      gradient_mid: "#ECF2FB",
      gradient_end: "#F8FAFC",
      sidebar_logo: "/images/ledgr-logos/logo/ledgr-logo.png",
      sidebar_logo_bg: true,
      card_logo: "/images/ledgr-logos/logo/ledgr-logo.png",
      tab_title: "Ledgr HQ",
      favicon: "/images/ledgr-logos/icon/ledgr-icon.png"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def account_codes do
    %{
      cash: "1000",
      bank_transfer: "1010",
      accounts_receivable: "1100",
      owners_equity: "3000",
      retained_earnings: "3050",
      owners_drawings: "3100",
      subscription_revenue: "4000",
      hosting_expense: "5100",
      domain_dns_expense: "5110",
      saas_tools_expense: "5120",
      general_expense: "5200",
      contractor_expense: "5300",
      legal_expense: "5400",
      marketing_expense: "5500"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def journal_entry_types do
    [
      {"Subscription Payment", "subscription_payment"},
      {"Subscription Refund", "subscription_refund"},
      {"Hosting Payment", "hosting_payment"},
      {"Tool/Service Payment", "tool_payment"},
      {"Contractor Payment", "contractor_payment"},
      {"Legal/Compliance", "legal_payment"},
      {"Marketing Expense", "marketing_expense"}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def menu_items do
    prefix = path_prefix()

    [
      %{group: "Main Menu", items: [
        %{label: "Dashboard",      path: prefix,                                             icon: :dashboard},
        %{label: "Clients",        path: "#{prefix}/clients",                               icon: :customers},
        %{label: "Subscriptions",  path: "#{prefix}/client-subscriptions?status=active",    icon: :subscriptions}
      ]},
      %{group: "Products", items: [
        %{label: "Plans",   path: "#{prefix}/subscription-plans", icon: :services},
        %{label: "Costs",   path: "#{prefix}/costs",              icon: :expenses}
      ]},
      %{group: "Finance", items: [
        %{label: "Expenses", path: "#{prefix}/expenses", icon: :expenses}
      ]}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def seed_file, do: nil

  @impl Ledgr.Domain.DomainConfig
  def has_active_dependencies?(_customer_id), do: false

  # ── RevenueHandler callbacks (stubs) ──────────────────────────────

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
  def dashboard_metrics(_start_date, _end_date) do
    alias Ledgr.Domains.LedgrHQ.{Clients, ClientSubscriptions, Costs}
    alias Ledgr.Core.Expenses

    all_clients = Clients.list_clients()
    active_clients = Enum.filter(all_clients, &(&1.status in ["active", "trial"]))

    today = Date.utc_today()
    month_start = %Date{today | day: 1}

    churned_this_month =
      Enum.count(all_clients, fn c ->
        c.ended_on != nil &&
          c.ended_on.year == today.year &&
          c.ended_on.month == today.month
      end)

    mrr_cents = ClientSubscriptions.mrr_cents()
    arr_cents = mrr_cents * 12
    monthly_costs_cents = Costs.total_monthly_cents()
    total_expenses_cents = Expenses.total_expenses_cents(month_start, today)
    total_opex_cents = monthly_costs_cents + total_expenses_cents
    net_margin_cents = mrr_cents - total_opex_cents
    active_count = length(active_clients)

    cost_per_client_cents =
      if active_count > 0, do: div(total_opex_cents, active_count), else: 0

    recent_clients =
      all_clients
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(5)

    %{
      mrr_cents: mrr_cents,
      arr_cents: arr_cents,
      active_clients_count: active_count,
      total_clients_count: length(all_clients),
      churned_this_month: churned_this_month,
      monthly_costs_cents: monthly_costs_cents,
      total_expenses_cents: total_expenses_cents,
      total_opex_cents: total_opex_cents,
      net_margin_cents: net_margin_cents,
      cost_per_client_cents: cost_per_client_cents,
      recent_clients: recent_clients
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
    today = Date.utc_today()
    start_of_year = %Date{today | month: 1, day: 1}
    {start_of_year, today}
  end

  @impl Ledgr.Domain.DashboardProvider
  def verification_checks, do: %{}

  @impl Ledgr.Domain.DashboardProvider
  def delivered_order_count(_start_date, _end_date), do: 0
end
