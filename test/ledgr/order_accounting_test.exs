defmodule Ledgr.Domains.MrMunchMe.OrderAccountingTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.MrMunchMe.OrderAccounting
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry
  alias Ledgr.Repo

  import Ledgr.Core.AccountingFixtures
  import Ledgr.Domains.MrMunchMe.OrdersFixtures
  import Ecto.Query

  # Extra accounts needed beyond standard_accounts_fixture
  defp extra_accounts_fixture do
    extras = [
      %{code: "1300", name: "Kitchen Equipment", type: "asset", normal_balance: "debit", is_cash: false},
      %{code: "2300", name: "Owed Change Payable", type: "liability", normal_balance: "credit", is_cash: false},
      %{code: "4010", name: "Sales Discounts", type: "revenue", normal_balance: "debit", is_cash: false},
      %{code: "6070", name: "Samples & Gifts", type: "expense", normal_balance: "debit", is_cash: false}
    ]

    Enum.each(extras, fn attrs ->
      case Accounting.get_account_by_code(attrs.code) do
        nil -> {:ok, _} = Accounting.create_account(attrs)
        _ -> :ok
      end
    end)
  end

  setup do
    accounts = standard_accounts_fixture()
    extra_accounts_fixture()
    product = product_fixture(%{name: "Cookie Box"})
    variant = variant_fixture(%{product: product, price_cents: 20000})
    location = location_fixture()

    {:ok, accounts: accounts, product: product, variant: variant, location: location}
  end

  describe "record_order_created/1" do
    test "is a no-op and returns :ok", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})
      assert :ok = OrderAccounting.record_order_created(order)
    end
  end

  describe "record_order_in_prep/2" do
    test "creates WIP journal entry from ingredients cost", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})
      cost_breakdown = %{ingredients: 5000, packing: 1000, kitchen: 0, total: 6000}

      assert {:ok, _entry} = OrderAccounting.record_order_in_prep(order, cost_breakdown)

      entry =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "order_in_prep" and je.reference == ^"Order ##{order.id}"
        )

      assert entry != nil
      assert entry.entry_type == "order_in_prep"
    end

    test "is idempotent — returns existing entry if already recorded", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})
      cost_breakdown = %{ingredients: 5000, packing: 0, kitchen: 0, total: 5000}

      {:ok, entry1} = OrderAccounting.record_order_in_prep(order, cost_breakdown)
      {:ok, entry2} = OrderAccounting.record_order_in_prep(order, cost_breakdown)

      assert entry1.id == entry2.id
    end

    test "skips zero-amount inventory lines", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})
      # Only ingredients, no packing or kitchen
      cost_breakdown = %{ingredients: 3000, packing: 0, kitchen: 0, total: 3000}

      assert {:ok, _entry} = OrderAccounting.record_order_in_prep(order, cost_breakdown)
    end
  end

  describe "record_order_delivered/1" do
    test "creates order_delivered journal entry for a basic sale order", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location, status: "delivered"})
      order = Repo.preload(order, :variant)

      assert {:ok, _entry} = OrderAccounting.record_order_delivered(order)

      entry =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "order_delivered" and je.reference == ^"Order ##{order.id}"
        )

      assert entry != nil
    end

    test "is idempotent — returns existing entry if already recorded", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location, status: "delivered"})
      order = Repo.preload(order, :variant)

      {:ok, entry1} = OrderAccounting.record_order_delivered(order)
      {:ok, entry2} = OrderAccounting.record_order_delivered(order)

      assert entry1.id == entry2.id
    end
  end

  describe "record_order_canceled/1" do
    test "returns :ok when order was never in_prep", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})
      assert :ok = OrderAccounting.record_order_canceled(order)
    end

    test "reverses WIP entry when order was in_prep", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})
      cost_breakdown = %{ingredients: 4000, packing: 1000, kitchen: 0, total: 5000}
      {:ok, _} = OrderAccounting.record_order_in_prep(order, cost_breakdown)

      assert {:ok, _reversal} = OrderAccounting.record_order_canceled(order)

      reversal =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "order_canceled" and je.reference == ^"Order ##{order.id}"
        )

      assert reversal != nil
    end

    test "is idempotent — returns existing reversal if already canceled", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})
      cost_breakdown = %{ingredients: 4000, packing: 0, kitchen: 0, total: 4000}
      {:ok, _} = OrderAccounting.record_order_in_prep(order, cost_breakdown)
      {:ok, reversal1} = OrderAccounting.record_order_canceled(order)
      {:ok, reversal2} = OrderAccounting.record_order_canceled(order)

      assert reversal1.id == reversal2.id
    end

    test "returns :ok when order was already delivered", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location, status: "delivered"})
      order = Repo.preload(order, :variant)
      cost_breakdown = %{ingredients: 4000, packing: 0, kitchen: 0, total: 4000}
      {:ok, _} = OrderAccounting.record_order_in_prep(order, cost_breakdown)
      {:ok, _} = OrderAccounting.record_order_delivered(order)

      assert :ok = OrderAccounting.record_order_canceled(order)
    end
  end

  describe "record_owed_change_ap/4" do
    test "creates owed_change_ap entry for delivered order (AR debit)", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location, status: "delivered"})

      assert {:ok, entry} = OrderAccounting.record_owed_change_ap(order, 500)
      assert entry.entry_type == "owed_change_ap"
    end

    test "creates owed_change_ap entry for deposit order (Customer Deposits debit)", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})

      assert {:ok, entry} = OrderAccounting.record_owed_change_ap(order, 500, nil, true)
      assert entry.entry_type == "owed_change_ap"
    end

    test "accepts explicit date", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})
      date = ~D[2025-01-15]

      assert {:ok, entry} = OrderAccounting.record_owed_change_ap(order, 1000, date, false)
      assert entry.date == date
    end
  end

  describe "handle_order_status_change/2" do
    test "returns :ok for new_order status", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})
      assert :ok = OrderAccounting.handle_order_status_change(order, "new_order")
    end

    test "returns :ok for unknown status", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})
      assert :ok = OrderAccounting.handle_order_status_change(order, "unknown_status")
    end

    test "returns :ok for delivered status on a basic order", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location, status: "delivered"})
      order = Repo.preload(order, :variant)
      assert {:ok, _} = OrderAccounting.handle_order_status_change(order, "delivered")
    end

    test "returns :ok for canceled when no in_prep entry exists", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})
      assert :ok = OrderAccounting.handle_order_status_change(order, "canceled")
    end
  end

  describe "revenue_by_product/2" do
    test "returns empty list when no delivered orders", %{} do
      today = Date.utc_today()
      result = OrderAccounting.revenue_by_product(today, today)
      assert result == []
    end

    test "aggregates revenue for delivered orders by product", %{variant: variant, location: location, product: product} do
      today = Date.utc_today()
      _order1 = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})
      _order2 = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})

      result = OrderAccounting.revenue_by_product(today, today)

      assert length(result) == 1
      row = hd(result)
      assert row.product_id == product.id
      # 2 orders × 20000 each = 40000
      assert row.revenue_cents == 40000
    end

    test "excludes non-delivered orders", %{variant: variant, location: location} do
      today = Date.utc_today()
      _order = order_fixture(%{variant: variant, location: location, status: "new_order", delivery_date: today})

      result = OrderAccounting.revenue_by_product(today, today)
      assert result == []
    end

    test "separates revenue by product", %{location: location} do
      today = Date.utc_today()
      product_a = product_fixture(%{name: "Product A"})
      variant_a = variant_fixture(%{product: product_a, price_cents: 10000})
      product_b = product_fixture(%{name: "Product B"})
      variant_b = variant_fixture(%{product: product_b, price_cents: 25000})

      _order_a = order_fixture(%{variant: variant_a, location: location, status: "delivered", delivery_date: today})
      _order_b = order_fixture(%{variant: variant_b, location: location, status: "delivered", delivery_date: today})

      result = OrderAccounting.revenue_by_product(today, today)
      assert length(result) == 2

      row_a = Enum.find(result, &(&1.product_id == product_a.id))
      assert row_a.revenue_cents == 10000

      row_b = Enum.find(result, &(&1.product_id == product_b.id))
      assert row_b.revenue_cents == 25000
    end
  end

  describe "cogs_by_product/2" do
    test "returns empty list when no delivered orders", %{} do
      today = Date.utc_today()
      result = OrderAccounting.cogs_by_product(today, today)
      assert result == []
    end

    test "returns product row with zero cogs when no in_prep entry exists", %{variant: variant, location: location, product: product} do
      today = Date.utc_today()
      _order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})

      result = OrderAccounting.cogs_by_product(today, today)
      assert length(result) == 1

      row = hd(result)
      assert row.product_id == product.id
      assert row.cogs_cents == 0
    end
  end

  describe "shipping_fee_cents/0" do
    test "returns a non-negative integer" do
      fee = OrderAccounting.shipping_fee_cents()
      assert is_integer(fee)
      assert fee >= 0
    end
  end

  describe "maybe_issue_stripe_refund/1" do
    test "returns :ok when order has no stripe session", %{variant: variant, location: location} do
      order = order_fixture(%{variant: variant, location: location})
      # stripe_checkout_session_id defaults to nil
      assert :ok = OrderAccounting.maybe_issue_stripe_refund(order)
    end
  end
end
