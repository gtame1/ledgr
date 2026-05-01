defmodule LedgrWeb.Domains.MrMunchMe.ApiController do
  @moduledoc """
  MrMunchMe-specific REST API controller for products, orders, inventory.
  """
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.{Inventory, Orders}

  # ---------- Products ----------

  def list_products(conn, _params) do
    products = Orders.list_all_products()

    json(conn, %{
      data: Enum.map(products, &serialize_product/1)
    })
  end

  def show_product(conn, %{"id" => id}) do
    product = Orders.get_product!(id)
    json(conn, %{data: serialize_product(product)})
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Product not found"})
  end

  # ---------- Orders ----------

  def list_orders(conn, params) do
    orders = Orders.list_orders(params)

    json(conn, %{
      data: Enum.map(orders, &serialize_order/1)
    })
  end

  def show_order(conn, %{"id" => id}) do
    order = Orders.get_order!(id)
    payment_summary = Orders.payment_summary(order)

    json(conn, %{
      data: serialize_order(order),
      payment_summary: %{
        product_total_cents: payment_summary.product_total_cents,
        shipping_cents: payment_summary.shipping_cents,
        order_total_cents: payment_summary.order_total_cents,
        total_paid_cents: payment_summary.total_paid_cents,
        outstanding_cents: payment_summary.outstanding_cents,
        fully_paid: payment_summary.fully_paid?,
        partially_paid: payment_summary.partially_paid?
      }
    })
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Order not found"})
  end

  # ---------- Inventory ----------

  def list_ingredients(conn, _params) do
    ingredients = Inventory.list_ingredients()

    json(conn, %{
      data: Enum.map(ingredients, &serialize_ingredient/1)
    })
  end

  def show_ingredient(conn, %{"id" => id}) do
    ingredient = Inventory.get_ingredient!(id)
    json(conn, %{data: serialize_ingredient(ingredient)})
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "Ingredient not found"})
  end

  def list_stock(conn, _params) do
    stock_items = Inventory.list_stock_items()

    json(conn, %{
      data: Enum.map(stock_items, &serialize_stock_item/1),
      total_value_cents: Inventory.total_inventory_value_cents()
    })
  end

  def list_locations(conn, _params) do
    locations = Inventory.list_locations()

    json(conn, %{
      data: Enum.map(locations, &serialize_location/1)
    })
  end

  # ---------- Serializers ----------

  defp serialize_product(product) do
    %{
      id: product.id,
      name: product.name,
      active: product.active,
      inserted_at: product.inserted_at,
      updated_at: product.updated_at
    }
  end

  defp serialize_variant(variant) do
    %{
      id: variant.id,
      name: variant.name,
      sku: variant.sku,
      price_cents: variant.price_cents,
      active: variant.active
    }
  end

  defp serialize_order(order) do
    variant = order.variant
    product = variant && variant.product

    %{
      id: order.id,
      customer_name: order.customer_name,
      customer_email: order.customer_email,
      customer_phone: order.customer_phone,
      delivery_type: order.delivery_type,
      delivery_address: order.delivery_address,
      delivery_date: order.delivery_date,
      delivery_time: order.delivery_time,
      status: order.status,
      customer_paid_shipping: order.customer_paid_shipping,
      quantity: order.quantity || 1,
      variant: variant && serialize_variant(variant),
      product: product && serialize_product(product),
      customer_id: order.customer_id,
      prep_location_id: order.prep_location_id,
      inserted_at: order.inserted_at,
      updated_at: order.updated_at
    }
  end

  defp serialize_ingredient(ingredient) do
    %{
      id: ingredient.id,
      code: ingredient.code,
      name: ingredient.name,
      unit: ingredient.unit,
      cost_per_unit_cents: ingredient.cost_per_unit_cents,
      inventory_type: ingredient.inventory_type,
      inserted_at: ingredient.inserted_at,
      updated_at: ingredient.updated_at
    }
  end

  defp serialize_stock_item(item) do
    %{
      id: item.id,
      ingredient:
        item.ingredient &&
          %{
            id: item.ingredient.id,
            code: item.ingredient.code,
            name: item.ingredient.name,
            unit: item.ingredient.unit
          },
      location:
        item.location &&
          %{
            id: item.location.id,
            code: item.location.code,
            name: item.location.name
          },
      quantity_on_hand: item.quantity_on_hand,
      avg_cost_per_unit_cents: item.avg_cost_per_unit_cents,
      value_cents: Inventory.inventory_item_value_cents(item.ingredient_id, item.location_id)
    }
  end

  defp serialize_location(location) do
    %{
      id: location.id,
      code: location.code,
      name: location.name,
      description: location.description
    }
  end
end
