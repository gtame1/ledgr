defmodule Ledgr.Domains.VolumeStudio do
  @moduledoc """
  Volume Studio domain configuration.

  A wellness studio that offers group classes, personal diet consultations,
  subscription memberships, and studio space rental to nutritionists.

  Revenue streams:
  - Subscriptions: multi-tier plans with class limits (deferred revenue → monthly recognition)
  - Classes: drop-in / one-off class payments
  - Consultations: diet consultation appointments (one-off)
  - Space rentals: studio space rented out to nutritionists

  This is a stub implementation — domain-specific features will be added in Phase 2.
  """

  @behaviour Ledgr.Domain.DomainConfig
  @behaviour Ledgr.Domain.RevenueHandler
  @behaviour Ledgr.Domain.DashboardProvider

  # ── DomainConfig callbacks ──────────────────────────────────────────

  @impl Ledgr.Domain.DomainConfig
  def name, do: "Volume Studio"

  @impl Ledgr.Domain.DomainConfig
  def slug, do: "volume-studio"

  @impl Ledgr.Domain.DomainConfig
  def path_prefix, do: "/app/volume-studio"

  @impl Ledgr.Domain.DomainConfig
  def logo, do: "🏋🏻"

  @impl Ledgr.Domain.DomainConfig
  def theme do
    %{
      sidebar_bg: "#546B7D",
      sidebar_text: "#F8F3EA",
      sidebar_hover: "#42566B",
      primary: "#546B7D",
      primary_soft: "#EDF0F4",
      accent: "#546B7D",
      bg: "#F8F3EA",
      bg_surface: "#F0EBE0",
      border_subtle: "#E2D9CC",
      border_strong: "#C8BFAF",
      text_main: "#282828",
      text_muted: "#706A62",
      btn_secondary_bg: "#E2D9CC",
      btn_secondary_text: "#282828",
      btn_secondary_hover: "#C8BFAF",
      btn_primary_hover: "#42566B",
      shadow_color: "40, 40, 40",
      table_header_bg: "#F0EBE0",
      gradient_start: "#EDF0F4",
      gradient_mid: "#F5F1EB",
      gradient_end: "#F8F3EA",
      sidebar_logo: "/images/volume-studio-logos/logo/main-logo.png",
      card_logo: "/images/volume-studio-logos/logo/main-logo.png",
      tab_title: "Volume Studio",
      favicon: "/images/favicon-volume-studio.png"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def account_codes do
    %{
      cash: "1000",
      accounts_receivable: "1100",
      iva_receivable: "1400",
      iva_payable: "2100",
      deferred_subscription_revenue: "2200",
      owners_equity: "3000",
      retained_earnings: "3050",
      owners_drawings: "3100",
      subscription_revenue: "4000",
      class_revenue: "4010",
      consultation_revenue: "4020",
      rental_revenue: "4030"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def journal_entry_types do
    [
      {"Subscription Payment", "subscription_payment"},
      {"Subscription Revenue Recognition", "subscription_revenue_recognition"},
      {"Class Payment", "class_payment"},
      {"Consultation Payment", "consultation_payment"},
      {"Space Rental Payment", "space_rental_payment"}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def menu_items do
    prefix = path_prefix()

    [
      %{group: "Main Menu", items: [
        %{label: "Dashboard", path: prefix, icon: :dashboard}
      ]},
      %{group: "Members", items: [
        %{label: "Customers", path: "#{prefix}/customers", icon: :customers},
        %{label: "Subscriptions", path: "#{prefix}/subscriptions", icon: :subscriptions}
      ]},
      %{group: "Studio", items: [
        %{label: "Class Sessions", path: "#{prefix}/class-sessions", icon: :bookings},
        %{label: "Instructors", path: "#{prefix}/instructors", icon: :users},
        %{label: "Consultations", path: "#{prefix}/consultations", icon: :documents}
      ]},
      %{group: "Spaces", items: [
        %{label: "Spaces & Rentals", path: "#{prefix}/spaces", icon: :services}
      ]},
      %{group: "Finance", items: [
        %{label: "Expenses", path: "#{prefix}/expenses", icon: :expenses},
        %{label: "Transactions", path: "#{prefix}/transactions", icon: :transactions}
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

  # ── DashboardProvider callbacks (stubs) ───────────────────────────

  @impl Ledgr.Domain.DashboardProvider
  def dashboard_metrics(start_date, end_date) do
    pnl = Ledgr.Core.Accounting.profit_and_loss(start_date, end_date)

    %{
      total_orders: 0,
      total_units: 0,
      delivered_orders: 0,
      orders_by_status: %{},
      orders_by_product: [],
      revenue_cents: 0,
      avg_order_value_cents: 0,
      inventory_summary: %{total_value_cents: 0, total_items: 0, by_type: []},
      pnl: pnl
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
