defmodule Ledgr.Domains.Viaxe do
  @moduledoc """
  Viaxe domain configuration.

  A travel agency business that manages bookings, supplier relationships,
  and commission-based revenue.

  This is a stub implementation — full features will be added in Phase 3.
  """

  @behaviour Ledgr.Domain.DomainConfig
  @behaviour Ledgr.Domain.RevenueHandler
  @behaviour Ledgr.Domain.DashboardProvider

  # ── DomainConfig callbacks ──────────────────────────────────────────

  @impl Ledgr.Domain.DomainConfig
  def name, do: "Viaxe"

  @impl Ledgr.Domain.DomainConfig
  def slug, do: "viaxe"

  @impl Ledgr.Domain.DomainConfig
  def path_prefix, do: "/app/viaxe"

  @impl Ledgr.Domain.DomainConfig
  # No public storefront — custom domain root falls back to login
  def public_home, do: nil

  @impl Ledgr.Domain.DomainConfig
  def logo, do: "✈️"

  @impl Ledgr.Domain.DomainConfig
  def theme do
    %{
      sidebar_bg: "#060a3a",
      sidebar_text: "#f5f5f5",
      sidebar_hover: "#131963",
      primary: "#1e40af",
      primary_soft: "#e8edf8",
      accent: "#3b82f6",
      bg: "#f8fafc",
      bg_surface: "#f1f5f9",
      border_subtle: "#e2e8f0",
      border_strong: "#cbd5e1",
      text_main: "#1e293b",
      text_muted: "#64748b",
      btn_secondary_bg: "#e2e8f0",
      btn_secondary_text: "#1e293b",
      btn_secondary_hover: "#cbd5e1",
      btn_primary_hover: "#1e3a8a",
      shadow_color: "30, 41, 59",
      table_header_bg: "#f1f5f9",
      gradient_start: "#dbeafe",
      gradient_mid: "#f0f5ff",
      gradient_end: "#f8fafc",
      sidebar_logo: "/images/viaxe-logos/Viaxe-D5.png",
      card_logo: "/images/viaxe-logos/Viaxe-D4.png",
      tab_title: "Viaxe App",
      favicon: "/images/favicon-viaxe.png"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def account_codes do
    %{
      cash: "1000",
      commission_receivable: "1100",
      advance_commission: "2200",
      commission_revenue: "4000",
      owners_equity: "3000",
      retained_earnings: "3050",
      owners_drawings: "3100"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def journal_entry_types do
    [
      {"Booking Payment", "booking_payment"},
      {"Booking Completed", "booking_completed"},
      {"Booking Canceled", "booking_canceled"}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def menu_items do
    prefix = path_prefix()

    [
      %{
        group: "Main Menu",
        items: [
          %{label: "Dashboard", path: prefix, icon: :dashboard},
          %{label: "Customers", path: "#{prefix}/customers", icon: :customers},
          %{label: "Trips", path: "#{prefix}/trips", icon: :trips}
        ]
      },
      %{
        group: "Travel",
        items: [
          %{label: "Bookings", path: "#{prefix}/bookings", icon: :bookings},
          %{label: "Services", path: "#{prefix}/services", icon: :services},
          %{label: "Suppliers", path: "#{prefix}/suppliers", icon: :suppliers},
          %{label: "Recommendations", path: "#{prefix}/recommendations", icon: :recommendations},
          %{label: "Documents", path: "#{prefix}/documents", icon: :documents}
        ]
      },
      %{
        group: "Finance",
        items: [
          %{label: "Expenses", path: "#{prefix}/expenses", icon: :expenses}
        ]
      }
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def seed_file, do: nil

  @impl Ledgr.Domain.DomainConfig
  def has_active_dependencies?(_customer_id), do: false

  # ── RevenueHandler callbacks ───────────────────────────────────────

  alias Ledgr.Domains.Viaxe.Bookings.BookingAccounting

  @impl Ledgr.Domain.RevenueHandler
  def handle_status_change(booking, new_status),
    do: BookingAccounting.handle_status_change(booking, new_status)

  @impl Ledgr.Domain.RevenueHandler
  def record_payment(payment), do: BookingAccounting.record_booking_payment(payment)

  @impl Ledgr.Domain.RevenueHandler
  def revenue_breakdown(_start_date, _end_date), do: []

  @impl Ledgr.Domain.RevenueHandler
  def cogs_breakdown(_start_date, _end_date), do: []

  # ── DashboardProvider callbacks (stubs) ───────────────────────────

  @impl Ledgr.Domain.DashboardProvider
  def dashboard_metrics(start_date, end_date) do
    # Return basic P&L-only metrics for now
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
