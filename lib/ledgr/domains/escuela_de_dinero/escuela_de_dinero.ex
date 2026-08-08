defmodule Ledgr.Domains.EscuelaDeDinero do
  @moduledoc """
  Escuela de Dinero domain configuration.

  "Socio" is a WhatsApp bot for self-employed Mexicans — people who invoice
  rather than draw a salary. It runs a six-question *diagnóstico*, delivers one
  headline number (`dias_sin_facturar` — how many days you last without
  invoicing), a per-área status, and three *movimientos*, then stays on for
  months of *acompañamiento* nudging those movimientos to `hecho`.

  This domain is **operational only**: no accounting, no P&L, no balance sheet.
  The bot has no payments tables at all. It is also **read-only** — there are no
  POST routes, so Ledgr can never corrupt the bot's data.

  Because it doesn't route `LedgrWeb.ReportController`, it is the first domain
  whose `/` is its own `DashboardController` and which skips the `core_routes`
  macros entirely. That works because implementing `nav_icons/0` suppresses the
  shared Reports/Tools nav groups — which also means `menu_items/0` is the sole
  source of navigation, so anything not listed there is unreachable.

  ## Vocabulary

  The brand manual bans school words outright — never *curso, módulo, lección,
  clase, alumno, inscripción, temario, generación, certificado* — and never
  *educación financiera*, *asesoría en inversiones* or *recomendación
  personalizada* (the last two describe regulated activities in Mexico).
  Authorized: *diagnóstico, movimiento, acompañamiento, guía, sistema,
  instalación, paso*. Keep UI copy inside that vocabulary.
  """

  @behaviour Ledgr.Domain.DomainConfig
  @behaviour Ledgr.Domain.RevenueHandler
  @behaviour Ledgr.Domain.DashboardProvider

  @timezone "America/Mexico_City"

  @doc "Today's date in Mexico City — the timezone every bot timestamp is read in."
  def today do
    DateTime.now!(@timezone) |> DateTime.to_date()
  end

  @doc "The timezone all bot TIMESTAMPTZ values are bucketed into for reporting."
  def timezone, do: @timezone

  # ── DomainConfig callbacks ──────────────────────────────────────────

  @impl Ledgr.Domain.DomainConfig
  def name, do: "Escuela de Dinero"

  @impl Ledgr.Domain.DomainConfig
  def slug, do: "escuela-de-dinero"

  @impl Ledgr.Domain.DomainConfig
  def path_prefix, do: "/app/escuela-de-dinero"

  @impl Ledgr.Domain.DomainConfig
  def public_home, do: nil

  # Only a fallback — theme[:sidebar_logo] wins wherever it's set.
  @impl Ledgr.Domain.DomainConfig
  def logo, do: "\u{1F4B5}"

  @impl Ledgr.Domain.DomainConfig
  def sidebar_subtitle, do: "Socio"

  @impl Ledgr.Domain.DomainConfig
  def theme do
    %{
      # Brand v3 "Rótulo Callejero" — Mexican hand-painted sign writing.
      # Source of truth: escuela-de-dinero-landing/src/app/globals.css.
      # Proportion rule: 55% cal/papel · 25% verde · 10% ladrillo · 8% oro · 2% azul.

      # Verde rótulo
      sidebar_bg: "#123b2b",
      # Cal
      sidebar_text: "#efe2c7",
      # Verde claro
      sidebar_hover: "#1d4732",
      primary: "#123b2b",
      # Papel
      primary_soft: "#f2e4c6",
      # Oro — accent, never a surface under long text
      accent: "#d8a62e",
      # Cal — page bg
      bg: "#efe2c7",
      # Papel alto
      bg_surface: "#fffaf0",
      border_subtle: "#e6d5b3",
      # Papel marco
      border_strong: "#d5c099",
      # Tinta
      text_main: "#171611",
      # Humo
      text_muted: "#7d735e",
      btn_secondary_bg: "#f2e4c6",
      btn_secondary_text: "#171611",
      btn_secondary_hover: "#d5c099",
      # Verde hondo
      btn_primary_hover: "#0a291e",
      # Verde as an RGB triple — no leading '#', it goes into rgba().
      shadow_color: "18, 59, 43",
      table_header_bg: "#f2e4c6",
      gradient_start: "#f2e4c6",
      gradient_mid: "#f6ecd6",
      gradient_end: "#efe2c7",
      tab_title: "Escuela de Dinero",
      # Logos (v3 brand pack):
      #   - favicon / sidebar icon / /apps tile → the "E$" isotipo
      #   - login + sidebar wordmark            → the painted lockup
      # Both marks are painted for a cream ground, so the wide wordmark sits on
      # a cal panel inside the verde sidebar.
      favicon: "/images/escuela-de-dinero-logos/main-icon.png",
      sidebar_logo: "/images/escuela-de-dinero-logos/main-icon.png",
      sidebar_logo_wide: "/images/escuela-de-dinero-logos/horizontal-logo.png",
      sidebar_logo_wide_bg: "#efe2c7",
      card_logo: "/images/escuela-de-dinero-logos/main-icon.png",
      auth_logo: "/images/escuela-de-dinero-logos/horizontal-logo.png",
      # Stitch extended tokens
      ct_surface: "#efe2c7",
      ct_surface_container: "#fffaf0",
      ct_surface_container_high: "#f2e4c6",
      ct_on_surface: "#171611",
      ct_on_surface_variant: "#7d735e",
      ct_outline_variant: "#e6d5b3",
      ct_primary_container: "#123b2b",
      ct_primary_fixed: "#f2e4c6",
      ct_secondary_container: "#f6ecd6",
      # Ladrillo — riesgo y números negativos, nunca decorativo
      ct_error: "#a83c2b",
      ct_font_headline: "Bodoni Moda"
    }
  end

  # No accounting in this domain. `account_codes/0` has no callers outside
  # domain modules; `journal_entry_types/0` is flat-mapped across every
  # registered domain by Ledgr.Core.Accounting.JournalEntry, so it must be a list.
  @impl Ledgr.Domain.DomainConfig
  def account_codes, do: %{}

  @impl Ledgr.Domain.DomainConfig
  def journal_entry_types, do: []

  @impl Ledgr.Domain.DomainConfig
  def menu_items do
    prefix = path_prefix()

    [
      %{
        group: "Operación",
        items: [
          %{label: "Panel", path: prefix, icon: :dashboard},
          %{label: "Personas", path: "#{prefix}/personas", icon: :customers},
          %{label: "Diagnósticos", path: "#{prefix}/diagnosticos", icon: :reports},
          %{label: "Movimientos", path: "#{prefix}/movimientos", icon: :reports},
          %{label: "Conversaciones", path: "#{prefix}/conversaciones", icon: :receipt},
          %{label: "Calidad", path: "#{prefix}/calidad", icon: :reports},
          %{label: "Kubo", path: "#{prefix}/kubo", icon: :reports}
        ]
      }
    ]
  end

  # Every menu_items/0 label needs an entry here or it silently falls back to
  # the generic "article" icon. There's a test that asserts this.
  @impl Ledgr.Domain.DomainConfig
  def nav_icons do
    %{
      "Panel" => "dashboard",
      "Personas" => "group",
      "Diagnósticos" => "monitor_heart",
      "Movimientos" => "checklist",
      "Conversaciones" => "chat",
      "Calidad" => "verified_user",
      "Kubo" => "link"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def seed_file, do: "priv/repos/escuela_de_dinero/seeds.exs"

  # No customers table in this domain — the bot's `people` are not Ledgr
  # customers, and nothing routes the shared CustomerController.
  @impl Ledgr.Domain.DomainConfig
  def has_active_dependencies?(_customer_id), do: false

  # ── RevenueHandler callbacks ────────────────────────────────────────
  #
  # There is no revenue here. The bot has no payments tables; the only
  # money-adjacent table is `kubo_referrals`, which carries no amounts.

  @impl Ledgr.Domain.RevenueHandler
  def handle_status_change(_record, _new_status), do: :ok

  @impl Ledgr.Domain.RevenueHandler
  def record_payment(_payment), do: :ok

  @impl Ledgr.Domain.RevenueHandler
  def revenue_breakdown(_start_date, _end_date), do: []

  @impl Ledgr.Domain.RevenueHandler
  def cogs_breakdown(_start_date, _end_date), do: []

  # ── DashboardProvider callbacks ────────────────────────────────────
  #
  # Nothing routes ReportController, so these are only reachable from IEx.
  # dashboard_metrics/2 still delegates for real — it's a useful REPL entry
  # point and keeps the behaviour honest.

  @impl Ledgr.Domain.DashboardProvider
  def dashboard_metrics(start_date, end_date) do
    Ledgr.Domains.EscuelaDeDinero.DashboardMetrics.all(start_date, end_date)
  end

  @impl Ledgr.Domain.DashboardProvider
  def unit_economics(_product_id, _start_date, _end_date), do: nil

  @impl Ledgr.Domain.DashboardProvider
  def all_unit_economics(_start_date, _end_date), do: []

  @impl Ledgr.Domain.DashboardProvider
  def product_select_options, do: []

  @impl Ledgr.Domain.DashboardProvider
  def data_date_range do
    # No journal_entries table (no accounting in this domain), so there's no
    # ledger to derive a real range from. Default to a 90-day window.
    today = today()
    {Date.add(today, -90), today}
  end

  @impl Ledgr.Domain.DashboardProvider
  def verification_checks, do: %{}

  @impl Ledgr.Domain.DashboardProvider
  def delivered_order_count(_start_date, _end_date), do: 0
end
