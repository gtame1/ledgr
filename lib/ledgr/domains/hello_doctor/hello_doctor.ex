defmodule Ledgr.Domains.HelloDoctor do
  @moduledoc """
  HelloDoctor domain configuration.

  A WhatsApp-based healthcare marketplace connecting patients with doctors
  on-demand. Main revenue stream is consultation charges with a 15% commission.
  """

  @behaviour Ledgr.Domain.DomainConfig
  @behaviour Ledgr.Domain.RevenueHandler
  @behaviour Ledgr.Domain.DashboardProvider

  @timezone "America/Mexico_City"

  def today do
    DateTime.now!(@timezone) |> DateTime.to_date()
  end

  # ── DomainConfig callbacks ──────────────────────────────────────────

  @impl Ledgr.Domain.DomainConfig
  def name, do: "HelloDoctor"

  @impl Ledgr.Domain.DomainConfig
  def slug, do: "hello-doctor"

  @impl Ledgr.Domain.DomainConfig
  def path_prefix, do: "/app/hello-doctor"

  @impl Ledgr.Domain.DomainConfig
  def public_home, do: nil

  @impl Ledgr.Domain.DomainConfig
  def logo, do: "\u{1FA7A}"

  @impl Ledgr.Domain.DomainConfig
  def theme do
    %{
      # HelloDoctor brand palette
      sidebar_bg: "#004058",
      sidebar_text: "#ffffff",
      sidebar_hover: "#005a7a",
      primary: "#004058",
      primary_soft: "#d0eef9",
      accent: "#02ba97",
      bg: "#f5f7f9",
      bg_surface: "#ffffff",
      border_subtle: "#e2e8f0",
      border_strong: "#cbd5e1",
      text_main: "#141414",
      text_muted: "#64748b",
      btn_secondary_bg: "#e2e8f0",
      btn_secondary_text: "#141414",
      btn_secondary_hover: "#cbd5e1",
      btn_primary_hover: "#003347",
      shadow_color: "0, 64, 88",
      table_header_bg: "#f1f5f9",
      gradient_start: "#d0eef9",
      gradient_mid: "#f0f9ff",
      gradient_end: "#f5f7f9",
      tab_title: "HelloDoctor",
      favicon: "/images/hello-doctor-logos/Hello-Doctor-Icon.png",
      sidebar_logo: "/images/hello-doctor-logos/Hello-Doctor-Icon.png",
      card_logo: "/images/hello-doctor-logos/Hello-Doctor-Logo.png",
      # Stitch extended tokens
      ct_surface: "#f5f7f9",
      ct_surface_container: "#ffffff",
      ct_surface_container_high: "#f1f5f9",
      ct_on_surface: "#141414",
      ct_on_surface_variant: "#64748b",
      ct_outline_variant: "#e2e8f0",
      ct_primary_container: "#004058",
      ct_primary_fixed: "#d0eef9",
      ct_secondary_container: "#d0f5ed",
      ct_error: "#dc2626",
      ct_font_headline: "Manrope"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def account_codes do
    %{
      # Assets
      cash: "1000",
      ar: "1100",
      stripe_receivable: "1200",
      # Liabilities
      doctor_payable: "2000",
      refunds_payable: "2100",
      # Equity
      owners_equity: "3000",
      retained_earnings: "3050",
      # Revenue
      consultation_revenue: "4000",
      commission_revenue: "4100",
      # Expenses
      payment_processing: "6000",
      refunds_expense: "6010",
      operating_expense: "6020"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def journal_entry_types do
    [
      {"Consultation Payment", "consultation_payment"},
      {"Doctor Payout", "doctor_payout"},
      {"Refund", "refund"},
      {"Commission", "commission"},
      {"Operating Expense", "operating_expense"}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def menu_items do
    prefix = path_prefix()

    [
      %{group: "Main", items: [
        %{label: "Dashboard",      path: prefix,                       icon: :dashboard},
        %{label: "Conversations",  path: "#{prefix}/conversations",    icon: :receipt},
        %{label: "Consultations",  path: "#{prefix}/consultations",    icon: :receipt},
        %{label: "Doctors",        path: "#{prefix}/doctors",          icon: :customers},
        %{label: "Patients",       path: "#{prefix}/patients",         icon: :customers}
      ]},
      %{group: "Finance", items: [
        %{label: "Payments",       path: "#{prefix}/payments",         icon: :expenses},
        %{label: "Expenses",       path: "#{prefix}/expenses",         icon: :expenses},
        %{label: "Balance Sheet",  path: "#{prefix}/reports/balance_sheet", icon: :reports},
        %{label: "P&L",            path: "#{prefix}/reports/pnl",      icon: :reports}
      ]},
      %{group: "Settings", items: [
        %{label: "Specialties",         path: "#{prefix}/specialties",               icon: :customers},
        %{label: "Transactions",        path: "#{prefix}/transactions",              icon: :transactions},
        %{label: "Reconciliation",      path: "#{prefix}/reconciliation/accounting", icon: :reconciliation}
      ]}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def seed_file, do: "priv/repos/hello_doctor/seeds/hello_doctor_seeds.exs"

  @impl Ledgr.Domain.DomainConfig
  def has_active_dependencies?(_customer_id), do: false

  # ── RevenueHandler callbacks ────────────────────────────────────────

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
    Ledgr.Domains.HelloDoctor.DashboardMetrics.all(start_date, end_date)
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
