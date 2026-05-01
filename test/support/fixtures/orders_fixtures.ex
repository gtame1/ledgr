defmodule Ledgr.Domains.MrMunchMe.OrdersFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Ledgr.Domains.MrMunchMe.Orders` context.
  """

  alias Ledgr.Domains.MrMunchMe.Orders
  alias Ledgr.Repo
  alias Ledgr.Domains.MrMunchMe.Orders.{Product, ProductVariant, Order}
  alias Ledgr.Domains.MrMunchMe.Inventory.Location

  @doc """
  Generate a product (no sku/price_cents — those live on variants now).
  """
  def product_fixture(attrs \\ %{}) do
    {:ok, product} =
      %Product{}
      |> Product.changeset(
        Enum.into(attrs, %{
          name: "Test Product",
          active: true
        })
      )
      |> Repo.insert()

    product
  end

  @doc """
  Generate a product variant.

  Accepts an optional `:product` key with an existing product; otherwise creates one.
  All other keys are forwarded to the variant changeset.
  """
  def variant_fixture(attrs \\ %{}) do
    product = attrs[:product] || product_fixture()

    {:ok, variant} =
      %ProductVariant{}
      |> ProductVariant.changeset(
        attrs
        |> Map.drop([:product])
        |> Enum.into(%{
          name: "Standard",
          sku: "TEST-VAR-#{System.unique_integer([:positive])}",
          price_cents: 10000,
          active: true,
          product_id: product.id
        })
      )
      |> Repo.insert()

    variant
  end

  @doc """
  Generate a location for order prep.
  """
  def location_fixture(attrs \\ %{}) do
    {:ok, location} =
      %Location{}
      |> Location.changeset(
        Enum.into(attrs, %{
          code: "LOC_#{System.unique_integer([:positive])}",
          name: "Test Location"
        })
      )
      |> Repo.insert()

    location
  end

  @doc """
  Generate an order with minimal required fields.

  Accepts:
  - `:variant` — an existing `ProductVariant` struct (preferred)
  - `:product` — an existing `Product` struct; a default variant will be created for it
  - `:location` — an existing `Location` struct; one is created if omitted
  All other keys are merged into the order changeset attrs.
  """
  def order_fixture(attrs \\ %{}) do
    variant =
      cond do
        Map.has_key?(attrs, :variant) ->
          attrs[:variant]

        Map.has_key?(attrs, :product) ->
          variant_fixture(%{product: attrs[:product]})

        true ->
          variant_fixture()
      end

    location = attrs[:location] || location_fixture()

    order_attrs =
      attrs
      |> Map.drop([:variant, :location, :product])
      |> Enum.into(%{
        customer_name: "Test Customer",
        customer_phone: "5551234567",
        variant_id: variant.id,
        prep_location_id: location.id,
        delivery_date: Date.utc_today(),
        delivery_type: "pickup",
        status: "new_order"
      })

    {:ok, order} =
      %Order{}
      |> Order.changeset(order_attrs)
      |> Repo.insert()

    order |> Repo.preload(variant: :product, prep_location: [], customer: [])
  end

  @doc """
  Generate an order using the full Orders.create_order/1 function.
  This triggers all the business logic (customer lookup, accounting, etc.)
  """
  def order_with_full_creation(attrs \\ %{}) do
    variant =
      cond do
        Map.has_key?(attrs, :variant) ->
          attrs[:variant]

        Map.has_key?(attrs, :product) ->
          variant_fixture(%{product: attrs[:product]})

        true ->
          variant_fixture()
      end

    location = attrs[:location] || location_fixture()

    order_attrs =
      attrs
      |> Map.drop([:variant, :location, :product])
      |> Enum.into(%{
        "customer_name" => "Test Customer",
        "customer_phone" => "5551234567",
        "variant_id" => to_string(variant.id),
        "prep_location_id" => to_string(location.id),
        "delivery_date" => Date.to_iso8601(Date.utc_today()),
        "delivery_type" => "pickup",
        "status" => "new_order"
      })

    Orders.create_order(order_attrs)
  end

  @doc """
  Generate an order payment.
  """
  def order_payment_fixture(order, account, attrs \\ %{}) do
    payment_attrs =
      attrs
      |> Enum.into(%{
        "order_id" => to_string(order.id),
        "paid_to_account_id" => to_string(account.id),
        "amount_cents" => 5000,
        "payment_date" => Date.to_iso8601(Date.utc_today()),
        "is_deposit" => false
      })

    {:ok, payment} = Orders.create_order_payment(payment_attrs)
    payment
  end
end
