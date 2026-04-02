defmodule Ledgr.Domains.VolumeStudio do
  @moduledoc """
  Volume Studio domain configuration.

  A wellness studio that offers group classes, personal diet consultations,
  subscription memberships, and studio space rental to nutritionists.

  Revenue streams:
  - Subscriptions: multi-tier plans with class limits (deferred revenue → monthly/per-class recognition)
  - Consultations: diet consultation appointments (one-off)
  - Space rentals: studio space rented out to nutritionists
  - Partner fees: per-session fees collected from partners/instructors (account 4040)
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
  # No public storefront — custom domain root falls back to login
  def public_home, do: nil

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
      favicon: "/images/volume-studio-logos/icon/PNG/ISOTIPO-1.png"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def account_codes do
    %{
      cash: "1000",
      bank_transfer: "1010",
      card_terminal: "1020",
      accounts_receivable: "1100",
      iva_receivable: "1400",
      iva_payable: "2100",
      deferred_subscription_revenue: "2200",
      owed_change_payable: "2300",
      owners_equity: "3000",
      retained_earnings: "3050",
      owners_drawings: "3100",
      subscription_revenue: "4000",
      consultation_revenue: "4020",
      rental_revenue: "4030",
      partner_fee_revenue: "4040"
    }
  end

  @doc """
  Returns the list of accounts available as "paid to" destinations on payment forms.
  Format: [{display_label, account_code}]
  """
  def paid_to_account_options do
    [
      {"Cash (drawer)", "1000"},
      {"Bank Transfer", "1010"},
      {"Card Terminal", "1020"}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def journal_entry_types do
    [
      {"Subscription Payment", "subscription_payment"},
      {"Subscription Payment Reversal", "subscription_payment_reversal"},
      {"Subscription Revenue Recognition", "subscription_revenue_recognition"},
      {"Subscription Refund", "subscription_refund"},
      {"Owed Change AP", "owed_change_ap"},
      {"Change Given", "change_given"},
      {"Consultation Payment", "consultation_payment"},
      {"Consultation Owed Change AP", "consultation_owed_change_ap"},
      {"Consultation Change Given", "consultation_change_given"},
      {"Space Rental Payment", "space_rental_payment"},
      {"Rental Owed Change AP", "rental_owed_change_ap"},
      {"Rental Change Given", "rental_change_given"},
      {"Partner Fee", "partner_fee"}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def menu_items do
    prefix = path_prefix()

    [
      %{group: "Main Menu", items: [
        %{label: "Dashboard",      path: prefix,                                       icon: :dashboard},
        %{label: "Class Sessions", path: "#{prefix}/class-sessions?status=scheduled", icon: :bookings},
        %{label: "Class Calendar", path: "#{prefix}/class-sessions/calendar",         icon: :bookings},
        %{label: "Subscriptions",  path: "#{prefix}/subscriptions?status=active",     icon: :subscriptions},
        %{label: "Quick Sale",     path: "#{prefix}/quick-sale/new",                  icon: :receipt}
      ]},
      %{group: "Studio & Spaces", items: [
        %{label: "Members",             path: "#{prefix}/customers",           icon: :customers},
        %{label: "Instructors",         path: "#{prefix}/instructors",         icon: :users},
        %{label: "Consultations",       path: "#{prefix}/consultations",       icon: :documents},
        %{label: "Subscription Plans",  path: "#{prefix}/subscription-plans",  icon: :services},
        %{label: "Spaces",              path: "#{prefix}/spaces",              icon: :services},
        %{label: "Rentals",             path: "#{prefix}/space-rentals",       icon: :receipt}
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

  @doc """
  Cascades a soft-delete to all Volume Studio records belonging to the given customer.
  Called automatically by Customers.delete_customer/1 before soft-deleting the customer row.
  """
  def on_customer_soft_delete(customer_id, now) do
    import Ecto.Query
    alias Ledgr.Repo
    alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
    alias Ledgr.Domains.VolumeStudio.ClassSessions.ClassBooking
    alias Ledgr.Domains.VolumeStudio.Consultations.Consultation
    alias Ledgr.Domains.VolumeStudio.Spaces.SpaceRental

    from(r in Subscription, where: r.customer_id == ^customer_id and is_nil(r.deleted_at))
    |> Repo.update_all(set: [deleted_at: now, updated_at: now])

    from(r in ClassBooking, where: r.customer_id == ^customer_id and is_nil(r.deleted_at))
    |> Repo.update_all(set: [deleted_at: now, updated_at: now])

    from(r in Consultation, where: r.customer_id == ^customer_id and is_nil(r.deleted_at))
    |> Repo.update_all(set: [deleted_at: now, updated_at: now])

    from(r in SpaceRental, where: r.customer_id == ^customer_id and is_nil(r.deleted_at))
    |> Repo.update_all(set: [deleted_at: now, updated_at: now])

    :ok
  end

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
  def dashboard_metrics(start_date, end_date) do
    alias Ledgr.Domains.VolumeStudio.{ClassSessions, Subscriptions}

    pnl = Ledgr.Core.Accounting.profit_and_loss(start_date, end_date)

    today        = LedgrWeb.Helpers.DomainHelpers.today_mx()
    next_7_days  = Date.add(today, 7)
    next_30_days = Date.add(today, 30)

    from_dt        = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
    to_7_dt        = DateTime.new!(next_7_days, ~T[23:59:59], "Etc/UTC")
    period_from_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    period_to_dt   = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    upcoming_sessions = ClassSessions.list_class_sessions(from: from_dt, to: to_7_dt, status: "scheduled")
    period_sessions   = ClassSessions.list_class_sessions(from: period_from_dt, to: period_to_dt)

    active_subs = Subscriptions.list_subscriptions(status: "active")

    expiring_soon_count =
      Enum.count(active_subs, fn sub ->
        sub.ends_on &&
          Date.compare(sub.ends_on, today) != :lt &&
          Date.compare(sub.ends_on, next_30_days) != :gt
      end)

    sessions_by_status =
      period_sessions
      |> Enum.group_by(& &1.status)
      |> Map.new(fn {k, v} -> {k, length(v)} end)

    %{
      pnl: pnl,
      upcoming_sessions: upcoming_sessions,
      active_subscriptions_count: length(active_subs),
      expiring_soon_count: expiring_soon_count,
      period_sessions_count: length(period_sessions),
      sessions_by_status: sessions_by_status
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
