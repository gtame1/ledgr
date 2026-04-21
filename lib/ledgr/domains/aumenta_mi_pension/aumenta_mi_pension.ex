defmodule Ledgr.Domains.AumentaMiPension do
  @moduledoc """
  Aumenta Mi Pensión domain configuration.

  A WhatsApp-based pension advisory product for IMSS (Ley 73) affiliates in
  Mexico. AI triages prospects, a human agent closes the sale via paid
  consultation, and the customer walks away with a Modalidad 40 plan.
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
  def name, do: "Aumenta Mi Pensión"

  @impl Ledgr.Domain.DomainConfig
  def slug, do: "aumenta-mi-pension"

  @impl Ledgr.Domain.DomainConfig
  def path_prefix, do: "/app/aumenta-mi-pension"

  @impl Ledgr.Domain.DomainConfig
  def public_home, do: nil

  @impl Ledgr.Domain.DomainConfig
  def logo, do: "\u{1F331}"

  @impl Ledgr.Domain.DomainConfig
  def theme do
    %{
      # Brand palette v1.1 — verde bosque + crema (see Brand Manual v1.1).
      sidebar_bg: "#1B4332",       # Verde Profundo
      sidebar_text: "#F5F2EA",     # Crema
      sidebar_hover: "#2D6A4F",    # Verde Bosque
      primary: "#2D6A4F",          # Verde Bosque — CTAs, logos
      primary_soft: "#D8F3DC",     # Verde Suave — card bg, badges
      accent: "#74C69D",           # Verde Menta — highlights, íconos
      bg: "#F5F2EA",               # Crema — page bg
      bg_surface: "#FFFFFF",
      border_subtle: "#F0EDE4",    # Arena
      border_strong: "#D8D3C4",
      text_main: "#3D2C1E",        # Tierra Oscura
      text_muted: "#8B7355",       # Tierra Medio
      btn_secondary_bg: "#F0EDE4",
      btn_secondary_text: "#3D2C1E",
      btn_secondary_hover: "#D8D3C4",
      btn_primary_hover: "#1B4332",
      shadow_color: "45, 106, 79",
      table_header_bg: "#F0EDE4",
      gradient_start: "#D8F3DC",
      gradient_mid: "#ECF6EC",
      gradient_end: "#F5F2EA",
      tab_title: "Aumenta Mi Pensión",
      # Logos:
      #   - favicon     → main-icon.png (sharp PNG, square)
      #   - sidebar     → white-icon.jpeg (sits on dark verde bosque bg)
      #   - /apps tile  → main-icon.png (square, icon-sized)
      #   - login/auth  → horizontal-logo.png (full wordmark, wider banner)
      favicon: "/images/aumenta-mi-pension-logos/main-icon.png",
      sidebar_logo: "/images/aumenta-mi-pension-logos/white-icon.jpeg",
      sidebar_logo_wide: "/images/aumenta-mi-pension-logos/horizontal-logo.png",
      sidebar_logo_wide_bg: "#F5F2EA",
      card_logo: "/images/aumenta-mi-pension-logos/main-icon.png",
      auth_logo: "/images/aumenta-mi-pension-logos/horizontal-logo.png",
      # Stitch extended tokens
      ct_surface: "#F5F2EA",
      ct_surface_container: "#FFFFFF",
      ct_surface_container_high: "#F0EDE4",
      ct_on_surface: "#3D2C1E",
      ct_on_surface_variant: "#8B7355",
      ct_outline_variant: "#F0EDE4",
      ct_primary_container: "#2D6A4F",
      ct_primary_fixed: "#D8F3DC",
      ct_secondary_container: "#FFF4E6",
      ct_error: "#E07A2F",         # Ámbar — urgencia
      ct_font_headline: "DM Serif Display"
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
      agent_payable: "2000",
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
      {"Agent Payout", "agent_payout"},
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
        %{label: "Dashboard",       path: prefix,                       icon: :dashboard},
        %{label: "Conversations",   path: "#{prefix}/conversations",    icon: :receipt},
        %{label: "Pension Cases",   path: "#{prefix}/pension-cases",    icon: :reports},
        %{label: "Consultations",   path: "#{prefix}/consultations",    icon: :receipt},
        %{label: "Agent Chats",     path: "#{prefix}/agent-chats",      icon: :receipt},
        %{label: "Agents",          path: "#{prefix}/agents",           icon: :customers},
        %{label: "Customers",       path: "#{prefix}/customers",        icon: :customers}
      ]},
      %{group: "Finance", items: [
        %{label: "Payments",        path: "#{prefix}/payments",         icon: :expenses},
        %{label: "Balance Sheet",   path: "#{prefix}/reports/balance_sheet", icon: :reports},
        %{label: "P&L",             path: "#{prefix}/reports/pnl",      icon: :reports}
      ]}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def sidebar_subtitle, do: "Modalidad 40"

  @impl Ledgr.Domain.DomainConfig
  def nav_icons do
    %{
      "Dashboard" => "dashboard",
      "Conversations" => "chat",
      "Pension Cases" => "description",
      "Consultations" => "medical_services",
      "Agent Chats" => "forum",
      "Agents" => "support_agent",
      "Customers" => "group",
      "Payments" => "payments",
      "Balance Sheet" => "account_balance",
      "P&L" => "bar_chart"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def seed_file, do: "priv/repos/aumenta_mi_pension/seeds.exs"

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
    Ledgr.Domains.AumentaMiPension.DashboardMetrics.all(start_date, end_date)
  end

  @impl Ledgr.Domain.DashboardProvider
  def unit_economics(_product_id, _start_date, _end_date), do: nil

  @impl Ledgr.Domain.DashboardProvider
  def all_unit_economics(_start_date, _end_date), do: []

  @impl Ledgr.Domain.DashboardProvider
  def product_select_options, do: []

  @impl Ledgr.Domain.DashboardProvider
  def data_date_range do
    # AMP has no journal_entries table yet (accounting/CoA is out of scope for
    # iteration 1). Fall back to a sensible default window so the dashboard
    # doesn't blow up on a missing relation.
    today = today()
    {Date.add(today, -90), today}
  end

  @impl Ledgr.Domain.DashboardProvider
  def verification_checks, do: %{}

  @impl Ledgr.Domain.DashboardProvider
  def delivered_order_count(_start_date, _end_date), do: 0

  # ── Stripe config helper ────────────────────────────────────────────

  @doc "True if AMP Stripe env vars are configured. Used to guard payment actions."
  def stripe_configured? do
    not is_nil(Application.get_env(:ledgr, :aumenta_mi_pension_stripe_api_key))
  end
end
