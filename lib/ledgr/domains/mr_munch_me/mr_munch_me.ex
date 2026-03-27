defmodule Ledgr.Domains.MrMunchMe do
  @moduledoc """
  MrMunchMe domain configuration.

  A bakery-style business that sells baked goods, manages ingredient
  inventory, and recognizes revenue on order delivery.
  """

  @behaviour Ledgr.Domain.DomainConfig
  @behaviour Ledgr.Domain.RevenueHandler
  @behaviour Ledgr.Domain.DashboardProvider

  alias Ledgr.Domains.MrMunchMe.OrderAccounting

  # ── DomainConfig callbacks ──────────────────────────────────────────

  @impl Ledgr.Domain.DomainConfig
  def name, do: "MrMunchMe"

  @impl Ledgr.Domain.DomainConfig
  def slug, do: "mr-munch-me"

  @impl Ledgr.Domain.DomainConfig
  def path_prefix, do: "/app/mr-munch-me"

  @impl Ledgr.Domain.DomainConfig
  # Public storefront landing page (used when accessed via custom domain root)
  def public_home, do: "/mr-munch-me/menu"

  @impl Ledgr.Domain.DomainConfig
  def logo, do: "🍪"

  @impl Ledgr.Domain.DomainConfig
  def theme do
    %{
      sidebar_bg: "#3b1c1c",
      sidebar_text: "#faf0ed",
      sidebar_hover: "#572e2e",
      primary: "#6b2d2d",
      primary_soft: "#f5e0dc",
      accent: "#c47a6c",
      bg: "#fdf6f4",
      bg_surface: "#fef9f7",
      border_subtle: "#f0ddd8",
      border_strong: "#e0c7c0",
      text_main: "#3b1c1c",
      text_muted: "#8c6b63",
      btn_secondary_bg: "#f2ddd7",
      btn_secondary_text: "#3b1c1c",
      btn_secondary_hover: "#e8cdc5",
      btn_primary_hover: "#552222",
      shadow_color: "59, 28, 28",
      table_header_bg: "#fdf2ee",
      gradient_start: "#f5dbd3",
      gradient_mid: "#fdf6f4",
      gradient_end: "#fef9f7",
      sidebar_logo: "/images/mr-munchme-logos/mr-munchme-white-logo.jpeg",
      card_logo: "/images/mr-munchme-logos/mr-munchme-logo.jpg",
      tab_title: "MrMunchMe App",
      favicon: "/images/mr-munchme-logos/mr-munchme-icon-no-bg.png",
      og_description: "Pasteles, brownies y snacks artesanales. ¡Haz tu pedido en línea! · Delivery en CDMX 🍪"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def account_codes do
    %{
      ar: "1100",
      cash: "1000",
      ingredients_inventory: "1200",
      packing_inventory: "1210",
      wip_inventory: "1220",
      kitchen_inventory: "1300",
      customer_deposits: "2200",
      sales: "4000",
      sales_discounts: "4010",
      shipping_revenue: "4020",
      owners_equity: "3000",
      retained_earnings: "3050",
      owners_drawings: "3100",
      ingredients_cogs: "5000",
      packaging_cogs: "5010",
      inventory_waste: "6060",
      samples_gifts: "6070",
      other_expenses: "6099"
    }
  end

  @impl Ledgr.Domain.DomainConfig
  def journal_entry_types do
    [
      {"Order Created", "order_created"},
      {"Order in Prep", "order_in_prep"},
      {"Order Delivered", "order_delivered"},
      {"Order Canceled", "order_canceled"},
      {"Order Payment", "order_payment"},
      {"Owed Change AP", "owed_change_ap"}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def menu_items do
    prefix = path_prefix()

    [
      %{group: "Main Menu", items: [
        %{label: "Dashboard", path: prefix, icon: :dashboard},
        %{label: "All Orders", path: "#{prefix}/orders", icon: :orders},
        %{label: "Order Calendar", path: "#{prefix}/orders/calendar", icon: :calendar},
        %{label: "Inventory", path: "#{prefix}/inventory", icon: :inventory},
        %{label: "Shopping List", path: "#{prefix}/inventory/requirements", icon: :shopping},
        %{label: "Expenses", path: "#{prefix}/expenses", icon: :expenses}
      ]},
      %{group: "Materials", items: [
        %{label: "Product List", path: "#{prefix}/products", icon: :products},
        %{label: "Ingredient List", path: "#{prefix}/ingredients", icon: :ingredients},
        %{label: "Recepies", path: "#{prefix}/recipes", icon: :recipes}
      ]},
      %{group: "Promotions", items: [
        %{label: "Discount Codes", path: "#{prefix}/discount-codes", icon: :discount}
      ]}
    ]
  end

  @impl Ledgr.Domain.DomainConfig
  def seed_file, do: "priv/repos/mr_munch_me/seeds/mr_munch_me_seeds.exs"

  @impl Ledgr.Domain.DomainConfig
  def has_active_dependencies?(customer_id) do
    import Ecto.Query, warn: false
    alias Ledgr.Domains.MrMunchMe.Orders.Order

    Ledgr.Repo.exists?(
      from o in Order,
        where: o.customer_id == ^customer_id,
        where: o.status != "canceled"
    )
  end

  # ── RevenueHandler callbacks ────────────────────────────────────────

  @impl Ledgr.Domain.RevenueHandler
  def handle_status_change(order, new_status) do
    OrderAccounting.handle_order_status_change(order, new_status)
  end

  @impl Ledgr.Domain.RevenueHandler
  def record_payment(payment) do
    OrderAccounting.record_order_payment(payment)
  end

  @impl Ledgr.Domain.RevenueHandler
  def revenue_breakdown(start_date, end_date) do
    OrderAccounting.revenue_by_product(start_date, end_date)
  end

  @impl Ledgr.Domain.RevenueHandler
  def cogs_breakdown(start_date, end_date) do
    OrderAccounting.cogs_by_product(start_date, end_date)
  end

  # ── DashboardProvider callbacks ─────────────────────────────────────

  @impl Ledgr.Domain.DashboardProvider
  def dashboard_metrics(start_date, end_date) do
    Ledgr.Domains.MrMunchMe.Reporting.dashboard_metrics(start_date, end_date)
  end

  @impl Ledgr.Domain.DashboardProvider
  def unit_economics(product_id, start_date, end_date) do
    Ledgr.Domains.MrMunchMe.Reporting.unit_economics(product_id, start_date, end_date)
  end

  @impl Ledgr.Domain.DashboardProvider
  def all_unit_economics(start_date, end_date) do
    Ledgr.Domains.MrMunchMe.Reporting.all_unit_economics(start_date, end_date)
  end

  @impl Ledgr.Domain.DashboardProvider
  def product_select_options do
    Ledgr.Domains.MrMunchMe.Orders.product_select_options()
  end

  @impl Ledgr.Domain.DashboardProvider
  def data_date_range do
    {inv_earliest, inv_latest} = Ledgr.Domains.MrMunchMe.Inventory.movement_date_range()
    {je_earliest, je_latest} = Ledgr.Core.Accounting.journal_entry_date_range()

    dates = [inv_earliest, inv_latest, je_earliest, je_latest] |> Enum.reject(&is_nil/1)

    case dates do
      [] -> {nil, nil}
      _ -> {Enum.min(dates, Date), Enum.max(dates, Date)}
    end
  end

  @impl Ledgr.Domain.DashboardProvider
  def verification_checks do
    Ledgr.Domains.MrMunchMe.Inventory.Verification.run_all_checks()
  end

  @impl Ledgr.Domain.DashboardProvider
  def delivered_order_count(start_date, end_date) do
    import Ecto.Query

    from(o in "orders",
      where:
        o.status == "delivered" and
          fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) >= ^start_date and
          fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) <= ^end_date,
      select: count(o.id)
    )
    |> Ledgr.Repo.one() || 0
  end
end
