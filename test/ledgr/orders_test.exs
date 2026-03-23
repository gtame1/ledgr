defmodule Ledgr.Domains.MrMunchMe.OrdersTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.MrMunchMe.Orders
  alias Ledgr.Repo
  alias Ledgr.Domains.MrMunchMe.Orders.{Order, Product}

  import Ledgr.Domains.MrMunchMe.OrdersFixtures
  import Ledgr.Core.AccountingFixtures
  import Ledgr.Core.CustomersFixtures

  describe "products" do
    test "list_products/0 returns only active products" do
      product1 = product_fixture(%{name: "Active Product", active: true})
      _product2 = product_fixture(%{name: "Inactive Product", active: false})

      products = Orders.list_products()
      assert length(products) == 1
      assert hd(products).id == product1.id
    end

    test "list_all_products/0 returns all products including inactive" do
      _product1 = product_fixture(%{name: "Active Product", active: true})
      _product2 = product_fixture(%{name: "Inactive Product", active: false})

      products = Orders.list_all_products()
      assert length(products) == 2
    end

    test "get_product!/1 returns the product with given id" do
      product = product_fixture()
      assert Orders.get_product!(product.id).id == product.id
    end

    test "create_product/1 with valid data creates a product" do
      attrs = %{name: "New Product", active: true}
      assert {:ok, %Product{} = product} = Orders.create_product(attrs)
      assert product.name == "New Product"
    end

    test "create_product/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Orders.create_product(%{})
    end

    test "update_product/2 with valid data updates the product" do
      product = product_fixture()
      assert {:ok, %Product{} = updated} = Orders.update_product(product, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "product_select_options/0 returns formatted options" do
      product = product_fixture(%{name: "Test Product"})
      options = Orders.product_select_options()

      assert Enum.any?(options, fn {name, id} ->
        id == product.id && String.contains?(name, "Test Product")
      end)
    end

    test "variant_select_options/0 returns formatted variant options" do
      product = product_fixture(%{name: "Test Product"})
      variant = variant_fixture(%{product: product, name: "Grande"})

      options = Orders.variant_select_options()

      assert Enum.any?(options, fn {label, vid} ->
        vid == variant.id && String.contains?(label, "Test Product") && String.contains?(label, "Grande")
      end)
    end
  end

  describe "create_order/1" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 15000})
      location = location_fixture()

      {:ok, accounts: accounts, product: product, variant: variant, location: location}
    end

    test "creates order with valid data", %{variant: variant, location: location} do
      attrs = %{
        "customer_name" => "John Doe",
        "customer_phone" => "5551234567",
        "variant_id" => to_string(variant.id),
        "prep_location_id" => to_string(location.id),
        "delivery_date" => Date.to_iso8601(Date.utc_today()),
        "delivery_type" => "delivery",
        "delivery_address" => "123 Main St"
      }

      assert {:ok, %Order{} = order} = Orders.create_order(attrs)
      assert order.customer_name == "John Doe"
      assert order.customer_phone == "5551234567"
      assert order.status == "new_order"
      assert order.delivery_type == "delivery"
    end

    test "rejects new customer with existing phone, prompting to use existing customer list", %{variant: variant, location: location} do
      # Create a customer first
      _customer = customer_fixture(%{phone: "5559876543", name: "Existing Customer", email: "existing@test.com"})

      attrs = %{
        "customer_name" => "Different Name",
        "customer_phone" => "5559876543",
        "customer_email" => "different@test.com",
        "variant_id" => to_string(variant.id),
        "prep_location_id" => to_string(location.id),
        "delivery_date" => Date.to_iso8601(Date.utc_today()),
        "delivery_type" => "pickup"
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Orders.create_order(attrs)
      errors = errors_on(changeset)
      assert [msg] = errors[:customer_phone]
      assert msg =~ "already belongs to Existing Customer"
      assert msg =~ "existing customer list"
    end

    test "creates order with customer_id directly, syncing customer fields", %{variant: variant, location: location} do
      customer = customer_fixture(%{phone: "5551111111", name: "Real Name", email: "real@test.com"})

      attrs = %{
        "customer_id" => to_string(customer.id),
        "customer_name" => "Wrong Name",
        "customer_phone" => "0000000000",
        "variant_id" => to_string(variant.id),
        "prep_location_id" => to_string(location.id),
        "delivery_date" => Date.to_iso8601(Date.utc_today()),
        "delivery_type" => "pickup"
      }

      assert {:ok, %Order{} = order} = Orders.create_order(attrs)
      assert order.customer_id == customer.id
      # Denormalized fields should come from the customer record
      assert order.customer_name == "Real Name"
      assert order.customer_phone == "5551111111"
      assert order.customer_email == "real@test.com"
    end

    test "creates order with shipping", %{variant: variant, location: location} do
      attrs = %{
        "customer_name" => "Shipping Customer",
        "customer_phone" => "5552222222",
        "variant_id" => to_string(variant.id),
        "prep_location_id" => to_string(location.id),
        "delivery_date" => Date.to_iso8601(Date.utc_today()),
        "delivery_type" => "delivery",
        "customer_paid_shipping" => "true"
      }

      assert {:ok, %Order{} = order} = Orders.create_order(attrs)
      assert order.customer_paid_shipping == true
    end

    test "fails with missing required fields", %{variant: variant} do
      attrs = %{
        "customer_name" => "Test",
        "variant_id" => to_string(variant.id)
        # Missing prep_location_id, delivery_date, etc.
      }

      assert {:error, _changeset} = Orders.create_order(attrs)
    end
  end

  describe "order_total_cents/1" do
    setup do
      _accounts = standard_accounts_fixture()
      {:ok, %{}}
    end

    test "returns tuple with product price and zero shipping for pickup order" do
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 12000})
      order = order_fixture(%{variant: variant, delivery_type: "pickup", customer_paid_shipping: false})

      assert {12000, 0} = Orders.order_total_cents(order)
    end

    test "includes shipping in tuple for delivery order with customer_paid_shipping" do
      # Create the shipping variant required by Accounting.shipping_fee_cents()
      envio_product = product_fixture(%{name: "Shipping"})
      _envio_variant = variant_fixture(%{product: envio_product, sku: "ENVIO", price_cents: 5000})

      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 12000})
      location = location_fixture()

      # Create order directly with customer_paid_shipping set
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test",
          customer_phone: "5551234567",
          variant_id: variant.id,
          prep_location_id: location.id,
          delivery_date: Date.utc_today(),
          delivery_type: "delivery",
          status: "new_order",
          customer_paid_shipping: true
        })
        |> Repo.insert()

      # Reload order from database to ensure customer_paid_shipping is persisted
      order = Orders.get_order!(order.id)
      assert order.customer_paid_shipping == true

      {product_total, shipping} = Orders.order_total_cents(order)
      assert product_total == 12000
      assert shipping == 5000
    end

    test "returns zero shipping for delivery without customer_paid_shipping" do
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 12000})
      order = order_fixture(%{variant: variant, delivery_type: "delivery", customer_paid_shipping: false})

      assert {12000, 0} = Orders.order_total_cents(order)
    end

    test "applies flat discount (in pesos) to order total" do
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 12000})
      location = location_fixture()

      # Flat discount of $50 pesos = 5000 cents → 12000 - 5000 = 7000
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test",
          customer_phone: "5551234567",
          variant_id: variant.id,
          prep_location_id: location.id,
          delivery_date: Date.utc_today(),
          delivery_type: "pickup",
          status: "new_order",
          customer_paid_shipping: false,
          discount_type: "flat",
          discount_value: Decimal.new("50")
        })
        |> Repo.insert()

      assert {7000, 0} = Orders.order_total_cents(order)
    end

    test "applies percentage discount to order total" do
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 10000})
      location = location_fixture()

      # 10% discount → 10000 - 1000 = 9000
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test",
          customer_phone: "5551234567",
          variant_id: variant.id,
          prep_location_id: location.id,
          delivery_date: Date.utc_today(),
          delivery_type: "pickup",
          status: "new_order",
          customer_paid_shipping: false,
          discount_type: "percentage",
          discount_value: Decimal.new("10")
        })
        |> Repo.insert()

      assert {9000, 0} = Orders.order_total_cents(order)
    end

    test "discount applies to the full base price (unit price × quantity)" do
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 10000})
      location = location_fixture()

      # 2 units × 10000 = 20000 base; 25% off = 5000 discount → 15000
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test",
          customer_phone: "5551234567",
          variant_id: variant.id,
          prep_location_id: location.id,
          delivery_date: Date.utc_today(),
          delivery_type: "pickup",
          status: "new_order",
          customer_paid_shipping: false,
          quantity: 2,
          discount_type: "percentage",
          discount_value: Decimal.new("25")
        })
        |> Repo.insert()

      assert {15000, 0} = Orders.order_total_cents(order)
    end

    test "multi-quantity order without discount totals price × quantity" do
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 8000})
      order = order_fixture(%{variant: variant, delivery_type: "pickup", customer_paid_shipping: false, quantity: 3})

      # 3 × 8000 = 24000, no shipping
      assert {24000, 0} = Orders.order_total_cents(order)
    end
  end

  describe "payment_summary/1" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 10000})
      location = location_fixture()
      order = order_fixture(%{variant: variant, location: location})

      {:ok, accounts: accounts, order: order, cash_account: accounts["1000"]}
    end

    test "returns zero payments for order with no payments", %{order: order} do
      summary = Orders.payment_summary(order)

      assert summary.total_paid_cents == 0
      assert summary.outstanding_cents > 0
      assert summary.fully_paid? == false
      assert summary.partially_paid? == false
    end

    test "calculates partial payment correctly", %{order: order, cash_account: cash_account} do
      # Pay 5000 of 10000
      _payment = order_payment_fixture(order, cash_account, %{"amount_cents" => 5000})

      order = Orders.get_order!(order.id)
      summary = Orders.payment_summary(order)

      assert summary.total_paid_cents == 5000
      assert summary.outstanding_cents == 5000
      assert summary.fully_paid? == false
      assert summary.partially_paid? == true
    end

    test "marks as fully paid when total is covered", %{order: order, cash_account: cash_account} do
      # Pay full amount
      _payment = order_payment_fixture(order, cash_account, %{"amount_cents" => 10000})

      order = Orders.get_order!(order.id)
      summary = Orders.payment_summary(order)

      assert summary.total_paid_cents == 10000
      assert summary.outstanding_cents == 0
      assert summary.fully_paid? == true
    end

    test "handles multiple payments", %{order: order, cash_account: cash_account} do
      _payment1 = order_payment_fixture(order, cash_account, %{"amount_cents" => 3000})
      _payment2 = order_payment_fixture(order, cash_account, %{"amount_cents" => 7000})

      order = Orders.get_order!(order.id)
      summary = Orders.payment_summary(order)

      assert summary.total_paid_cents == 10000
      assert summary.fully_paid? == true
    end

    test "gift order shows order_total_cents of 0, outstanding 0, and fully_paid? true" do
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 10000})
      location = location_fixture()

      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Gift Recipient",
          customer_phone: "5551234567",
          variant_id: variant.id,
          prep_location_id: location.id,
          delivery_date: Date.utc_today(),
          delivery_type: "pickup",
          status: "new_order",
          customer_paid_shipping: false,
          is_gift: true
        })
        |> Repo.insert()

      order = Orders.get_order!(order.id)
      summary = Orders.payment_summary(order)

      assert summary.order_total_cents == 0
      assert summary.outstanding_cents == 0
      assert summary.fully_paid? == true
      assert summary.partially_paid? == false
      # No money was actually paid (it's a gift/comp)
      assert summary.total_paid_cents == 0
    end
  end

  describe "update_order_status/2" do
    # Note: Full status transition tests with inventory consumption
    # are in inventory_movement_accounting_test.exs
    # These tests focus on simpler transitions that don't require full recipe setup

    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 10000})
      location = location_fixture()

      {:ok, accounts: accounts, variant: variant, location: location}
    end

    test "transitions from in_prep to ready", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location, status: "in_prep"})

      assert {:ok, updated_order} = Orders.update_order_status(order, "ready")
      assert updated_order.status == "ready"
    end

    test "transitions from ready to delivered", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location, status: "ready"})

      assert {:ok, updated_order} = Orders.update_order_status(order, "delivered")
      assert updated_order.status == "delivered"
    end

    test "can cancel from new_order status", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location, status: "new_order"})

      assert {:ok, updated_order} = Orders.update_order_status(order, "canceled")
      assert updated_order.status == "canceled"
    end

    test "can cancel from ready status", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location, status: "ready"})

      assert {:ok, updated_order} = Orders.update_order_status(order, "canceled")
      assert updated_order.status == "canceled"
    end
  end

  describe "list_orders/1" do
    setup do
      _accounts = standard_accounts_fixture()
      product = product_fixture()
      variant = variant_fixture(%{product: product})
      location = location_fixture()

      order1 = order_fixture(%{variant: variant, location: location, status: "new_order"})
      order2 = order_fixture(%{variant: variant, location: location, status: "delivered"})
      order3 = order_fixture(%{variant: variant, location: location, status: "canceled"})

      {:ok, orders: [order1, order2, order3], product: product, variant: variant, non_canceled: [order1, order2]}
    end

    test "excludes canceled orders by default", %{non_canceled: non_canceled} do
      result = Orders.list_orders()
      # Should only return non-canceled orders
      assert length(result) >= length(non_canceled)
      assert Enum.all?(result, fn o -> o.status != "canceled" end)
    end

    test "filters by status", %{orders: [order1 | _]} do
      result = Orders.list_orders(%{"status" => "new_order"})

      assert Enum.any?(result, fn o -> o.id == order1.id end)
      assert Enum.all?(result, fn o -> o.status == "new_order" end)
    end

    test "filters by product_id", %{product: product} do
      result = Orders.list_orders(%{"product_id" => to_string(product.id)})

      assert Enum.all?(result, fn o -> o.variant.product_id == product.id end)
    end

    test "filters by date range" do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      tomorrow = Date.add(today, 1)

      result = Orders.list_orders(%{
        "date_from" => Date.to_iso8601(yesterday),
        "date_to" => Date.to_iso8601(tomorrow)
      })

      assert Enum.all?(result, fn o ->
        o.delivery_date >= yesterday and o.delivery_date <= tomorrow
      end)
    end
  end

  # ── Additional coverage ──────────────────────────────────────────────

  describe "list_canceled_orders/2" do
    test "returns orders with canceled status" do
      order = order_fixture(%{status: "canceled"})
      canceled = Orders.list_canceled_orders()
      assert Enum.any?(canceled, fn o -> o.id == order.id end)
    end

    test "respects limit parameter" do
      for _ <- 1..5, do: order_fixture(%{status: "canceled"})
      assert length(Orders.list_canceled_orders(3)) == 3
    end
  end

  describe "count_delivered_and_paid_orders/0" do
    test "returns integer count" do
      assert is_integer(Orders.count_delivered_and_paid_orders())
    end
  end

  describe "list_orders_for_calendar_month/3" do
    test "returns orders grouped by date" do
      today = Date.utc_today()
      order = order_fixture(%{delivery_date: today})

      result = Orders.list_orders_for_calendar_month(today.year, today.month)
      assert is_map(result)
      orders_on_date = Map.get(result, today, [])
      assert Enum.any?(orders_on_date, fn o -> o.id == order.id end)
    end

    test "returns empty map when no orders" do
      result = Orders.list_orders_for_calendar_month(2000, 1)
      assert result == %{}
    end
  end

  describe "update_order/2" do
    test "updates special instructions" do
      order = order_fixture()
      assert {:ok, updated} = Orders.update_order(order, %{special_instructions: "Extra icing"})
      assert updated.special_instructions == "Extra icing"
    end

    test "updates quantity" do
      order = order_fixture(%{quantity: 1})
      assert {:ok, updated} = Orders.update_order(order, %{quantity: 3})
      assert updated.quantity == 3
    end
  end

  describe "change_order/2" do
    test "returns a changeset" do
      order = order_fixture()
      assert %Ecto.Changeset{} = Orders.change_order(order, %{notes: "test"})
    end
  end

  describe "list_variants_for_product/1" do
    test "returns variants for a product" do
      product = product_fixture()
      variant = variant_fixture(%{product: product})

      variants = Orders.list_variants_for_product(product)
      assert Enum.any?(variants, fn v -> v.id == variant.id end)
    end
  end

  describe "list_products_with_variants/0" do
    test "returns products with variants preloaded" do
      product = product_fixture()
      _variant = variant_fixture(%{product: product})

      products = Orders.list_products_with_variants()
      found = Enum.find(products, fn p -> p.id == product.id end)
      assert found != nil
      assert is_list(found.variants)
      assert length(found.variants) > 0
    end
  end

  describe "list_active_variants/0" do
    test "returns only active variants" do
      active = variant_fixture(%{active: true})
      _inactive = variant_fixture(%{active: false})

      variants = Orders.list_active_variants()
      assert Enum.any?(variants, fn v -> v.id == active.id end)
      assert Enum.all?(variants, fn v -> v.active == true end)
    end
  end

  describe "order payment lifecycle" do
    setup do
      accounts = standard_accounts_fixture()
      variant = variant_fixture()
      location = location_fixture()
      order = order_fixture(%{variant: variant, location: location})
      cash = accounts["1000"]

      {:ok, order: order, cash_account: cash}
    end

    test "list_payments_for_order/1 returns empty when none", %{order: order} do
      assert Orders.list_payments_for_order(order.id) == []
    end

    test "create_order_payment/1 creates a payment", %{order: order, cash_account: cash} do
      assert {:ok, payment} =
               Orders.create_order_payment(%{
                 "order_id" => to_string(order.id),
                 "paid_to_account_id" => to_string(cash.id),
                 "amount_cents" => 5000,
                 "payment_date" => Date.to_iso8601(Date.utc_today()),
                 "is_deposit" => false
               })

      assert payment.amount_cents == 5000
    end

    test "list_payments_for_order/1 returns payments", %{order: order, cash_account: cash} do
      order_payment_fixture(order, cash)
      payments = Orders.list_payments_for_order(order.id)
      assert length(payments) >= 1
    end

    test "delete_order_payment/1 removes a payment", %{order: order, cash_account: cash} do
      payment = order_payment_fixture(order, cash)
      assert {:ok, _} = Orders.delete_order_payment(payment)
      assert Orders.list_payments_for_order(order.id) == []
    end
  end

  describe "update_order_ingredients/2" do
    test "replaces order ingredients" do
      order = order_fixture()
      location = Ledgr.Domains.MrMunchMe.Inventory.Location
                 |> Ledgr.Repo.one() || elem(Ledgr.Repo.insert!(%Ledgr.Domains.MrMunchMe.Inventory.Location{code: "WH", name: "Warehouse"}), 0)

      {:ok, updated} =
        Orders.update_order_ingredients(order, [
          %{"ingredient_code" => "FLOUR_TEST", "ingredient_name" => "Flour", "quantity" => 500, "location_code" => location.code},
          %{"ingredient_code" => "SUGAR_TEST", "ingredient_name" => "Sugar", "quantity" => 200, "location_code" => location.code}
        ])

      assert length(updated.order_ingredients) == 2
    end

    test "returns error with non-list attrs" do
      order = order_fixture()
      assert {:error, :invalid_attrs} = Orders.update_order_ingredients(order, "bad")
    end
  end
end
