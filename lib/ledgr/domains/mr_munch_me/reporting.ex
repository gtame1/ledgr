defmodule Ledgr.Domains.MrMunchMe.Reporting do
  @moduledoc """
  MrMunchMe-specific reporting: dashboard metrics, unit economics,
  and product-level KPIs.
  """

  import Ecto.Query, warn: false
  alias Ledgr.Repo

  alias Ledgr.Domains.MrMunchMe.Orders.{Order, Product}
  alias Ledgr.Domains.MrMunchMe.Orders
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry
  alias Ledgr.Domains.MrMunchMe.OrderAccounting
  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Domains.MrMunchMe.Inventory.InventoryMovement

  @doc """
  Returns metrics for the dashboard for a date range.

  * Uses order *delivery_date* for operational stats
  * Uses Accounting.profit_and_loss/2 for financial stats
  """
  def dashboard_metrics(start_date, end_date) do
    # --- Operational: orders + revenue (from orders/products) ---
    # Use actual_delivery_date for delivered orders, fall back to delivery_date for non-delivered
    order_rev_stats =
      from(o in Order,
        where:
          fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) >= ^start_date and
            fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) <= ^end_date and
            o.status != "canceled",
        select: %{
          order_count: count(o.id),
          unit_count: sum(fragment("COALESCE(?, 1)", o.quantity))
        }
      )
      |> Repo.one()

    # Revenue from orders – if you want to include shipping product, you can adjust later
    revenue_stats =
      from(o in Order,
        join: v in assoc(o, :variant),
        where:
          fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) >= ^start_date and
            fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) <= ^end_date and
            o.status != "canceled",
        select: %{
          revenue_cents: coalesce(sum(v.price_cents * fragment("COALESCE(?, 1)", o.quantity)), 0)
        }
      )
      |> Repo.one()

    active_by_status =
      from(o in Order,
        where: o.status in ["new_order", "in_prep", "ready"],
        group_by: o.status,
        select: {o.status, count(o.id)}
      )
      |> Repo.all()
      |> Enum.into(%{})

    completed_by_status =
      from(o in Order,
        where: o.status in ["delivered", "canceled"] and
          fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) >= ^start_date and
          fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) <= ^end_date,
        group_by: o.status,
        select: {o.status, count(o.id)}
      )
      |> Repo.all()
      |> Enum.into(%{})

    orders_by_status = Map.merge(active_by_status, completed_by_status)

    total_orders = order_rev_stats.order_count || 0
    total_units = order_rev_stats.unit_count || 0
    revenue_cents = revenue_stats.revenue_cents || 0

    avg_order_value_cents =
      if total_orders > 0 do
        div(revenue_cents, total_orders)
      else
        0
      end

    delivered_orders = Map.get(orders_by_status, "delivered", 0)

    # --- Orders per product with revenue and COGS ---
    # Fallback shipping fee for legacy orders that don't have it stored
    fallback_shipping_fee = OrderAccounting.shipping_fee_cents()

    orders_by_product_base =
      from(o in Order,
        join: v in assoc(o, :variant),
        join: p in assoc(v, :product),
        where:
          fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) >= ^start_date and
            fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) <= ^end_date and
            o.status != "canceled",
        group_by: [p.id, p.name],
        select: %{
          product_id: p.id,
          product_name: p.name,
          order_count: count(o.id),
          unit_count: sum(fragment("COALESCE(?, 1)", o.quantity)),
          revenue_cents: fragment("SUM(? * COALESCE(?, 1)) + SUM(CASE WHEN ? THEN COALESCE(?, ?) ELSE 0 END)", v.price_cents, o.quantity, o.customer_paid_shipping, o.shipping_fee_cents, ^fallback_shipping_fee)
        },
        order_by: [desc: count(o.id)]
      )
      |> Repo.all()

    # Get order IDs for each product to calculate COGS
    product_order_ids =
      orders_by_product_base
      |> Enum.map(fn product -> product.product_id end)
      |> Enum.uniq()

    # Get all orders for these products in the period
    all_orders =
      if Enum.empty?(product_order_ids) do
        []
      else
        from(o in Order,
          join: v in assoc(o, :variant),
          where:
            fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) >= ^start_date and
              fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) <= ^end_date and
              o.status != "canceled" and
              v.product_id in ^product_order_ids,
          select: o.id
        )
        |> Repo.all()
      end

    # Get COGS by order from journal entries
    cogs_by_order =
      if Enum.empty?(all_orders) do
        %{}
      else
        reference_patterns = Enum.map(all_orders, fn id -> "Order ##{id}" end)

        base_query =
          from(je in JournalEntry,
            join: jl in assoc(je, :journal_lines),
            join: acc in assoc(jl, :account),
            where:
              je.entry_type == "order_delivered" and
                acc.code == "5000" and
                je.date >= ^start_date and
                je.date <= ^end_date
          )

        # Use exact matching with IN clause instead of ilike patterns
        # ilike("Order #1") would wrongly match "Order #10", "Order #11", etc.
        query =
          case reference_patterns do
            [] ->
              base_query
            patterns ->
              base_query
              |> where([je], je.reference in ^patterns)
          end

        from([je, jl, acc] in query,
          group_by: je.reference,
          select: {je.reference, sum(jl.debit_cents)}
        )
        |> Repo.all()
        |> Enum.into(%{}, fn {ref, cogs} ->
          order_id =
            case Regex.run(~r/#(\d+)/, ref) do
              [_, id_str] -> String.to_integer(id_str)
              _ -> nil
            end
          {order_id, cogs || 0}
        end)
      end

    # Get product_id for each order to group COGS by product
    orders_with_products =
      if Enum.empty?(all_orders) do
        []
      else
        from(o in Order,
          join: v in assoc(o, :variant),
          where: o.id in ^all_orders,
          select: {o.id, v.product_id}
        )
        |> Repo.all()
      end

    # Group COGS by product
    cogs_by_product =
      orders_with_products
      |> Enum.reduce(%{}, fn {order_id, product_id}, acc ->
        cogs_cents = Map.get(cogs_by_order, order_id, 0)
        Map.update(acc, product_id, cogs_cents, &(&1 + cogs_cents))
      end)

    # Combine revenue and COGS
    orders_by_product =
      orders_by_product_base
      |> Enum.map(fn product ->
        revenue_cents =
          if is_integer(product.revenue_cents),
            do: product.revenue_cents,
            else: Decimal.to_integer(product.revenue_cents)

        cogs_cents = Map.get(cogs_by_product, product.product_id, 0)
        gross_profit_cents = revenue_cents - cogs_cents

        product
        |> Map.put(:revenue_cents, revenue_cents)
        |> Map.put(:cogs_cents, cogs_cents)
        |> Map.put(:gross_profit_cents, gross_profit_cents)
      end)

    # --- Inventory position summary ---
    inventory_summary = inventory_position_summary()

    # --- Financial: full P&L for same period ---
    pnl = Accounting.profit_and_loss(start_date, end_date)

    %{
      total_orders: total_orders,
      total_units: total_units,
      delivered_orders: delivered_orders,
      orders_by_status: orders_by_status,
      orders_by_product: orders_by_product,
      revenue_cents: revenue_cents,
      avg_order_value_cents: avg_order_value_cents,
      inventory_summary: inventory_summary,
      pnl: pnl
    }
  end

  defp inventory_position_summary do
    # Get all stock items with quantity > 0
    stock_items = Inventory.list_stock_items()
    |> Enum.filter(fn stock -> stock.quantity_on_hand > 0 end)

    # Batch-load all inventory values (4 queries instead of 4 × N)
    values_map = Inventory.batch_inventory_values()

    # Group by inventory type
    stock_by_type =
      stock_items
      |> Enum.group_by(fn stock ->
        Inventory.inventory_type(stock.ingredient.code)
      end)

    # Count items by type — use batch map for values, no extra DB calls
    counts_by_type =
      Enum.map(stock_by_type, fn {type, items} ->
        total_value = Enum.reduce(items, 0, fn stock, acc ->
          acc + Map.get(values_map, {stock.ingredient_id, stock.location_id}, 0)
        end)
        {type, %{count: length(items), total_value_cents: total_value}}
      end)
      |> Enum.into(%{})

    # Total value from the batch map
    total_value_cents =
      values_map
      |> Map.values()
      |> Enum.sum()

    %{
      total_value_cents: total_value_cents,
      by_type: counts_by_type,
      total_items: length(stock_items)
    }
  end

  @doc """
  Calculate unit economics for a specific product.
  Returns revenue, COGS, gross margin, expenses, net profit, per-variant breakdown,
  and per-ingredient COGS detail.
  """
  def unit_economics(product_id, start_date \\ nil, end_date \\ nil) do
    product =
      from(p in Product, where: p.id == ^product_id and is_nil(p.deleted_at))
      |> Repo.one!()

    # Default to all time if no dates provided
    {start_date, end_date} =
      case {start_date, end_date} do
        {nil, nil} -> {~D[2000-01-01], Date.utc_today()}
        {s, e} when not is_nil(s) and not is_nil(e) -> {s, e}
        {s, nil} -> {s, Date.utc_today()}
        {nil, e} -> {~D[2000-01-01], e}
      end

    # Get all delivered orders for this product
    orders =
      from(o in Order,
        join: v in assoc(o, :variant),
        where:
          v.product_id == ^product_id and
            fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) >= ^start_date and
            fragment("COALESCE(?, ?)", o.actual_delivery_date, o.delivery_date) <= ^end_date and
            o.status == "delivered",
        preload: [variant: v]
      )
      |> Repo.all()

    # Calculate revenue from orders
    revenue_cents =
      Enum.reduce(orders, 0, fn order, acc ->
        quantity = order.quantity || 1
        base_revenue = (order.variant.price_cents || 0) * quantity
        shipping_cents = if order.customer_paid_shipping, do: order.shipping_fee_cents || OrderAccounting.shipping_fee_cents(), else: 0
        acc + base_revenue + shipping_cents
      end)

    order_ids = Enum.map(orders, & &1.id)

    # Build per-order COGS map from journal entries (includes ingredients + packing)
    cogs_map =
      if Enum.empty?(order_ids) do
        %{}
      else
        reference_patterns = Enum.map(order_ids, fn id -> "Order ##{id}" end)

        from(je in JournalEntry,
          join: jl in assoc(je, :journal_lines),
          join: acc in assoc(jl, :account),
          where:
            je.entry_type == "order_delivered" and
              acc.code in ["5000", "5010"] and
              je.date >= ^start_date and
              je.date <= ^end_date and
              je.reference in ^reference_patterns,
          group_by: je.reference,
          select: {je.reference, sum(jl.debit_cents)}
        )
        |> Repo.all()
        |> Enum.into(%{}, fn {ref, cogs} ->
          order_id =
            case Regex.run(~r/#(\d+)/, ref) do
              [_, id_str] -> String.to_integer(id_str)
              _ -> nil
            end
          {order_id, cogs || 0}
        end)
      end

    cogs_cents = cogs_map |> Map.values() |> Enum.sum()

    # Build per-order discounts map from journal entries (account 4010 = Sales Discounts)
    discounts_map =
      if Enum.empty?(order_ids) do
        %{}
      else
        reference_patterns = Enum.map(order_ids, fn id -> "Order ##{id}" end)

        from(je in JournalEntry,
          join: jl in assoc(je, :journal_lines),
          join: acc in assoc(jl, :account),
          where:
            je.entry_type == "order_delivered" and
              acc.code == "4010" and
              je.date >= ^start_date and
              je.date <= ^end_date and
              je.reference in ^reference_patterns,
          group_by: je.reference,
          select: {je.reference, sum(jl.debit_cents)}
        )
        |> Repo.all()
        |> Enum.into(%{}, fn {ref, discount} ->
          order_id =
            case Regex.run(~r/#(\d+)/, ref) do
              [_, id_str] -> String.to_integer(id_str)
              _ -> nil
            end
          {order_id, discount || 0}
        end)
      end

    total_discounts_cents = discounts_map |> Map.values() |> Enum.sum()

    # Adjust revenue for discounts so it matches the P&L (gross price − discounts = net revenue)
    revenue_cents = revenue_cents - total_discounts_cents

    # Only use order IDs that actually have a COGS journal entry, so ingredient
    # breakdown totals are consistent with the COGS figure above.
    journalized_order_ids = cogs_map |> Map.keys() |> Enum.reject(&is_nil/1)

    # Calculate gross margin
    gross_margin_cents = revenue_cents - cogs_cents
    gross_margin_percent =
      if revenue_cents > 0 do
        Float.round(gross_margin_cents / revenue_cents * 100, 2)
      else
        0.0
      end

    # Get total expenses for the period (all expenses, not allocated to product)
    total_expenses_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        join: acc in assoc(jl, :account),
        where:
          je.entry_type == "expense" and
            acc.type == "expense" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Calculate number of units sold (sum quantities, not order count)
    units_sold = Enum.reduce(orders, 0, fn order, acc -> acc + (order.quantity || 1) end)

    # Calculate per-unit metrics
    revenue_per_unit_cents = if units_sold > 0, do: div(revenue_cents, units_sold), else: 0
    cogs_per_unit_cents = if units_sold > 0, do: div(cogs_cents, units_sold), else: 0
    gross_margin_per_unit_cents = if units_sold > 0, do: div(gross_margin_cents, units_sold), else: 0
    expenses_per_unit_cents = if units_sold > 0, do: div(total_expenses_cents, units_sold), else: 0

    # Net profit (revenue - COGS - expenses)
    net_profit_cents = gross_margin_cents - total_expenses_cents
    net_profit_per_unit_cents = if units_sold > 0, do: div(net_profit_cents, units_sold), else: 0
    net_margin_percent =
      if revenue_cents > 0 do
        Float.round(net_profit_cents / revenue_cents * 100, 2)
      else
        0.0
      end

    # Per-variant breakdown
    variants =
      orders
      |> Enum.group_by(fn order -> order.variant.id end)
      |> Enum.map(fn {_variant_id, variant_orders} ->
        variant = hd(variant_orders).variant
        v_units = Enum.reduce(variant_orders, 0, fn o, acc -> acc + (o.quantity || 1) end)
        v_revenue =
          Enum.reduce(variant_orders, 0, fn o, acc ->
            qty = o.quantity || 1
            base = (o.variant.price_cents || 0) * qty
            shipping = if o.customer_paid_shipping, do: o.shipping_fee_cents || OrderAccounting.shipping_fee_cents(), else: 0
            acc + base + shipping
          end)
        v_cogs = Enum.reduce(variant_orders, 0, fn o, acc -> acc + Map.get(cogs_map, o.id, 0) end)
        # Note: only orders in cogs_map contribute to v_cogs, consistent with top-level COGS.
        v_discount = Enum.reduce(variant_orders, 0, fn o, acc -> acc + Map.get(discounts_map, o.id, 0) end)
        v_revenue = v_revenue - v_discount
        v_gross_margin = v_revenue - v_cogs
        v_gross_margin_percent = if v_revenue > 0, do: Float.round(v_gross_margin / v_revenue * 100, 2), else: 0.0

        %{
          variant_name: variant.name,
          units_sold: v_units,
          revenue_cents: v_revenue,
          revenue_per_unit_cents: if(v_units > 0, do: div(v_revenue, v_units), else: 0),
          cogs_cents: v_cogs,
          cogs_per_unit_cents: if(v_units > 0, do: div(v_cogs, v_units), else: 0),
          gross_margin_cents: v_gross_margin,
          gross_margin_percent: v_gross_margin_percent
        }
      end)
      |> Enum.sort_by(& &1.variant_name)

    # Per-ingredient COGS from inventory movements.
    # Uses journalized_order_ids (orders with actual COGS journal entries) so
    # that ingredient totals sum to the same figure as the COGS row above.
    cogs_by_ingredient =
      if Enum.empty?(journalized_order_ids) do
        []
      else
        from(m in InventoryMovement,
          join: i in assoc(m, :ingredient),
          where:
            m.source_type == "order" and
              m.source_id in ^journalized_order_ids and
              m.movement_type == "usage",
          group_by: [i.id, i.name],
          select: %{
            ingredient_id: i.id,
            ingredient_name: i.name,
            total_cost_cents: sum(m.total_cost_cents)
          }
        )
        |> Repo.all()
        |> then(fn rows ->
          # If consume_for_order was called multiple times for the same order (e.g.
          # the order was re-set to in_prep), inventory movements are duplicated while
          # the COGS journal entry is only created once. Normalise proportionally so
          # ingredient totals always sum to the authoritative cogs_cents figure.
          raw_total = Enum.reduce(rows, 0, fn r, acc -> acc + (r.total_cost_cents || 0) end)
          scale = if raw_total > 0 and cogs_cents > 0, do: cogs_cents / raw_total, else: 1.0

          Enum.map(rows, fn row ->
            raw = row.total_cost_cents || 0
            total = round(raw * scale)
            percent = if cogs_cents > 0, do: Float.round(total / cogs_cents * 100, 2), else: 0.0
            cost_per_unit = if units_sold > 0, do: div(total, units_sold), else: 0
            row
            |> Map.put(:total_cost_cents, total)
            |> Map.put(:percent_of_cogs, percent)
            |> Map.put(:cost_per_unit_cents, cost_per_unit)
          end)
        end)
        |> Enum.sort_by(&(-(&1.total_cost_cents || 0)))
      end

    %{
      product: product,
      period: %{start_date: start_date, end_date: end_date},
      units_sold: units_sold,
      revenue_cents: revenue_cents,
      revenue_per_unit_cents: revenue_per_unit_cents,
      cogs_cents: cogs_cents,
      cogs_per_unit_cents: cogs_per_unit_cents,
      gross_margin_cents: gross_margin_cents,
      gross_margin_per_unit_cents: gross_margin_per_unit_cents,
      gross_margin_percent: gross_margin_percent,
      total_expenses_cents: total_expenses_cents,
      expenses_per_unit_cents: expenses_per_unit_cents,
      net_profit_cents: net_profit_cents,
      net_profit_per_unit_cents: net_profit_per_unit_cents,
      net_margin_percent: net_margin_percent,
      variants: variants,
      cogs_by_ingredient: cogs_by_ingredient
    }
  end

  @doc """
  Calculate unit economics for all active products.
  Returns a list of unit economics maps for each product.
  """
  def all_unit_economics(start_date \\ nil, end_date \\ nil) do
    # Default to all time if no dates provided
    {start_date, end_date} =
      case {start_date, end_date} do
        {nil, nil} -> {~D[2000-01-01], Date.utc_today()}
        {s, e} when not is_nil(s) and not is_nil(e) -> {s, e}
        {s, nil} -> {s, Date.utc_today()}
        {nil, e} -> {~D[2000-01-01], e}
      end

    # Get all active, non-deleted products
    products =
      from(p in Product,
        where: p.active == true and is_nil(p.deleted_at),
        order_by: [asc: p.name]
      )
      |> Repo.all()

    # Calculate unit economics for each product
    products
    |> Enum.map(fn product ->
      unit_economics(product.id, start_date, end_date)
    end)
    |> Enum.filter(fn ue -> ue.units_sold > 0 end)
  end

  @doc """
  AR Aging Report: shows outstanding receivables by age bucket.

  Returns:
    %{
      as_of_date: Date,
      total_outstanding_cents: integer,
      buckets: %{
        current: integer,      # 0-30 days
        days_31_60: integer,   # 31-60 days
        days_61_90: integer,   # 61-90 days
        over_90: integer       # 90+ days
      },
      line_items: [
        %{
          order_id: integer,
          customer_name: string,
          delivery_date: Date,
          days_outstanding: integer,
          order_total_cents: integer,
          paid_cents: integer,
          outstanding_cents: integer,
          bucket: string
        }
      ]
    }
  """
  def ar_aging_report(as_of_date \\ Date.utc_today()) do
    # Get all delivered orders with their payments preloaded
    delivered_orders =
      from(o in Order,
        where: o.status == "delivered",
        preload: [:order_payments]
      )
      |> Repo.all()

    line_items =
      delivered_orders
      |> Enum.map(fn order ->
        # Calculate order total (product + shipping)
        {product_cents, shipping_cents} = Orders.order_total_cents(order)
        order_total = product_cents + shipping_cents

        # Sum all payments (deposits + regular payments)
        paid_cents =
          Enum.reduce(order.order_payments, 0, fn payment, sum ->
            sum + (payment.amount_cents || 0)
          end)

        outstanding = order_total - paid_cents

        # Use actual_delivery_date if available, else delivery_date
        effective_date = order.actual_delivery_date || order.delivery_date
        days = if effective_date, do: Date.diff(as_of_date, effective_date), else: 0

        bucket =
          cond do
            days <= 30 -> "current"
            days <= 60 -> "31-60"
            days <= 90 -> "61-90"
            true -> "90+"
          end

        %{
          order_id: order.id,
          customer_name: order.customer_name,
          delivery_date: effective_date,
          days_outstanding: max(days, 0),
          order_total_cents: order_total,
          paid_cents: paid_cents,
          outstanding_cents: outstanding,
          bucket: bucket
        }
      end)
      # Only include orders with outstanding balance
      |> Enum.filter(fn item -> item.outstanding_cents > 0 end)
      |> Enum.sort_by(fn item -> -item.days_outstanding end)

    # Aggregate by bucket
    buckets =
      Enum.reduce(line_items, %{current: 0, days_31_60: 0, days_61_90: 0, over_90: 0}, fn item, acc ->
        case item.bucket do
          "current" -> %{acc | current: acc.current + item.outstanding_cents}
          "31-60" -> %{acc | days_31_60: acc.days_31_60 + item.outstanding_cents}
          "61-90" -> %{acc | days_61_90: acc.days_61_90 + item.outstanding_cents}
          "90+" -> %{acc | over_90: acc.over_90 + item.outstanding_cents}
        end
      end)

    total_outstanding =
      buckets.current + buckets.days_31_60 + buckets.days_61_90 + buckets.over_90

    %{
      as_of_date: as_of_date,
      total_outstanding_cents: total_outstanding,
      buckets: buckets,
      line_items: line_items
    }
  end
end
