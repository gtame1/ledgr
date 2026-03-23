defmodule Ledgr.Core.ReportingTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.{Reporting, Accounting}
  alias Ledgr.Domains.MrMunchMe.Reporting, as: DomainReporting
  alias Ledgr.Repo
  alias Ledgr.Domains.MrMunchMe.Orders.Order

  import Ledgr.Domains.MrMunchMe.OrdersFixtures
  import Ledgr.Core.AccountingFixtures

  describe "unit_economics/3" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture(%{name: "Test Product"})
      variant = variant_fixture(%{product: product, price_cents: 15000})
      location = location_fixture()

      {:ok, accounts: accounts, product: product, variant: variant, location: location}
    end

    test "returns metrics for product with no orders", %{product: product} do
      today = Date.utc_today()
      result = DomainReporting.unit_economics(product.id, today, today)

      assert result.product.id == product.id
      assert result.units_sold == 0
      assert result.revenue_cents == 0
      assert result.cogs_cents == 0
    end

    test "calculates revenue for delivered orders", %{product: product, variant: variant, location: location} do
      today = Date.utc_today()

      # Create a delivered order
      _order = order_fixture(%{variant: variant, location: location, status: "delivered"})

      result = DomainReporting.unit_economics(product.id, today, today)

      assert result.units_sold == 1
      assert result.revenue_cents == variant.price_cents
      assert result.revenue_per_unit_cents == variant.price_cents
    end

    test "includes shipping revenue when customer_paid_shipping is true", %{product: product, variant: variant, location: location} do
      # Create shipping variant
      envio_product = product_fixture(%{name: "Shipping"})
      _envio_variant = variant_fixture(%{product: envio_product, sku: "ENVIO", price_cents: 5000})

      today = Date.utc_today()

      # Create order with shipping
      {:ok, _order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test",
          customer_phone: "5551234567",
          variant_id: variant.id,
          prep_location_id: location.id,
          delivery_date: today,
          delivery_type: "delivery",
          status: "delivered",
          customer_paid_shipping: true
        })
        |> Repo.insert()

      result = DomainReporting.unit_economics(product.id, today, today)

      assert result.units_sold == 1
      # Revenue should be product variant price + shipping
      assert result.revenue_cents == variant.price_cents + 5000
    end

    test "excludes non-delivered orders from calculations", %{product: product, variant: variant, location: location} do
      today = Date.utc_today()

      # Create orders with different statuses
      _new_order = order_fixture(%{variant: variant, location: location, status: "new_order"})
      _in_prep = order_fixture(%{variant: variant, location: location, status: "in_prep"})
      _delivered = order_fixture(%{variant: variant, location: location, status: "delivered"})
      _canceled = order_fixture(%{variant: variant, location: location, status: "canceled"})

      result = DomainReporting.unit_economics(product.id, today, today)

      # Only the delivered order should count
      assert result.units_sold == 1
    end

    test "filters by date range", %{product: product, variant: variant, location: location} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      _tomorrow = Date.add(today, 1)

      # Create orders on different dates
      _yesterday_order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: yesterday})
      _today_order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})

      # Query only today
      result = DomainReporting.unit_economics(product.id, today, today)
      assert result.units_sold == 1

      # Query both days
      result_both = DomainReporting.unit_economics(product.id, yesterday, today)
      assert result_both.units_sold == 2
    end

    test "calculates gross margin correctly", %{product: product, variant: variant, location: location} do
      today = Date.utc_today()

      _order = order_fixture(%{variant: variant, location: location, status: "delivered"})

      result = DomainReporting.unit_economics(product.id, today, today)

      # With no COGS recorded, gross margin should equal revenue
      assert result.gross_margin_cents == result.revenue_cents - result.cogs_cents
    end

    test "defaults to all time when no dates provided", %{product: product, variant: variant, location: location} do
      # Create an order with today's date
      _order = order_fixture(%{variant: variant, location: location, status: "delivered"})

      result = DomainReporting.unit_economics(product.id, nil, nil)

      assert result.units_sold == 1
      assert result.period.start_date == ~D[2000-01-01]
    end
  end

  describe "cash_flow/2" do
    setup do
      accounts = standard_accounts_fixture()
      {:ok, accounts: accounts}
    end

    test "returns zero values when no cash transactions", %{accounts: _accounts} do
      today = Date.utc_today()
      result = Reporting.cash_flow(today, today)

      assert result.cash_inflows_cents == 0
      assert result.cash_outflows_cents == 0
      assert result.net_cash_flow_cents == 0
    end

    test "includes period in result", %{accounts: _accounts} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      result = Reporting.cash_flow(yesterday, today)

      assert result.period.start_date == yesterday
      assert result.period.end_date == today
    end

    test "records order payment inflows correctly", %{accounts: accounts} do
      today = Date.utc_today()
      cash = accounts["1000"]
      ar = accounts["1100"]

      # Simulate a cash receipt: Dr Cash, Cr AR
      {:ok, _entry} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "order_payment", reference: "Test", description: "Test payment"},
          [
            %{account_id: cash.id, debit_cents: 10000, credit_cents: 0, description: "Cash in"},
            %{account_id: ar.id, debit_cents: 0, credit_cents: 10000, description: "AR credit"}
          ]
        )

      result = Reporting.cash_flow(today, today)

      assert result.cash_inflows_cents == 10000
      assert result.breakdown.sales_inflows_cents == 10000
      assert result.net_cash_flow_cents == 10000
    end

    test "records expense outflows correctly", %{accounts: accounts} do
      today = Date.utc_today()
      cash = accounts["1000"]
      cogs = accounts["5000"]

      {:ok, _entry} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "expense", reference: "Test", description: "Test expense"},
          [
            %{account_id: cogs.id, debit_cents: 3000, credit_cents: 0, description: "COGS"},
            %{account_id: cash.id, debit_cents: 0, credit_cents: 3000, description: "Cash out"}
          ]
        )

      result = Reporting.cash_flow(today, today)

      assert result.cash_outflows_cents == 3000
      assert result.breakdown.expense_outflows_cents == 3000
      assert result.net_cash_flow_cents == -3000
    end

    test "excludes cash-to-cash transfers from inflows and outflows", %{accounts: accounts} do
      today = Date.utc_today()
      cash = accounts["1000"]
      # Create a second cash account
      cash2 = cash_account_fixture(%{code: "1001", name: "Bank Account"})

      {:ok, _entry} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "internal_transfer", reference: "Transfer", description: "Internal transfer"},
          [
            %{account_id: cash2.id, debit_cents: 5000, credit_cents: 0, description: "Bank in"},
            %{account_id: cash.id, debit_cents: 0, credit_cents: 5000, description: "Cash out"}
          ]
        )

      result = Reporting.cash_flow(today, today)

      # Cash-to-cash transfer should not appear in inflows or outflows
      assert result.cash_inflows_cents == 0
      assert result.cash_outflows_cents == 0
    end

    test "records investment inflows in financing section", %{accounts: accounts} do
      today = Date.utc_today()
      cash = accounts["1000"]
      equity = accounts["3000"]

      {:ok, _entry} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "investment", reference: "Investment", description: "Owner investment"},
          [
            %{account_id: cash.id, debit_cents: 50000, credit_cents: 0, description: "Cash in"},
            %{account_id: equity.id, debit_cents: 0, credit_cents: 50000, description: "Equity"}
          ]
        )

      result = Reporting.cash_flow(today, today)

      assert result.breakdown.investment_inflows_cents == 50000
      assert result.financing.inflows_cents == 50000
    end

    test "records withdrawal outflows in financing section", %{accounts: accounts} do
      today = Date.utc_today()
      cash = accounts["1000"]
      drawings = accounts["3100"]

      {:ok, _entry} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "withdrawal", reference: "Withdrawal", description: "Owner withdrawal"},
          [
            %{account_id: drawings.id, debit_cents: 20000, credit_cents: 0, description: "Drawings"},
            %{account_id: cash.id, debit_cents: 0, credit_cents: 20000, description: "Cash out"}
          ]
        )

      result = Reporting.cash_flow(today, today)

      assert result.breakdown.withdrawal_outflows_cents == 20000
      assert result.financing.outflows_cents == 20000
    end

    test "calculates beginning and ending balances correctly", %{accounts: accounts} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      cash = accounts["1000"]
      ar = accounts["1100"]

      # Add cash yesterday (before period)
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{date: yesterday, entry_type: "order_payment", reference: "Prior", description: "Prior payment"},
          [
            %{account_id: cash.id, debit_cents: 15000, credit_cents: 0, description: "Cash"},
            %{account_id: ar.id, debit_cents: 0, credit_cents: 15000, description: "AR"}
          ]
        )

      # Add cash today (inside period)
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "order_payment", reference: "Today", description: "Today payment"},
          [
            %{account_id: cash.id, debit_cents: 5000, credit_cents: 0, description: "Cash"},
            %{account_id: ar.id, debit_cents: 0, credit_cents: 5000, description: "AR"}
          ]
        )

      result = Reporting.cash_flow(today, today)

      assert result.beginning_balance_cents == 15000
      assert result.ending_balance_cents == 20000
      assert result.cash_inflows_cents == 5000
    end

    test "includes IAS 7 classification sections in result", %{accounts: _accounts} do
      today = Date.utc_today()
      result = Reporting.cash_flow(today, today)

      assert Map.has_key?(result, :operating)
      assert Map.has_key?(result, :investing)
      assert Map.has_key?(result, :financing)
      assert result.investing.inflows_cents == 0
      assert result.investing.outflows_cents == 0
    end
  end

  describe "financial_analysis/3" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 10000})
      location = location_fixture()

      {:ok, accounts: accounts, product: product, variant: variant, location: location}
    end

    test "returns all required sections", %{accounts: _accounts} do
      today = Date.utc_today()
      result = Reporting.financial_analysis(today, today)

      assert Map.has_key?(result, :period)
      assert Map.has_key?(result, :profitability)
      assert Map.has_key?(result, :efficiency)
      assert Map.has_key?(result, :leverage)
      assert Map.has_key?(result, :liquidity)
      assert Map.has_key?(result, :bakery)
      assert Map.has_key?(result, :raw)
    end

    test "returns zero profitability metrics with no transactions", %{accounts: _accounts} do
      today = Date.utc_today()
      result = Reporting.financial_analysis(today, today)

      assert result.profitability.gross_margin_percent == 0.0
      assert result.profitability.net_margin_percent == 0.0
      assert result.profitability.operating_margin_percent == 0.0
    end

    test "includes period dates in result", %{accounts: _accounts} do
      start_date = ~D[2025-01-01]
      end_date = ~D[2025-01-31]
      result = Reporting.financial_analysis(start_date, end_date)

      assert result.period.start_date == start_date
      assert result.period.end_date == end_date
    end

    test "calculates gross margin percent from revenue and COGS", %{accounts: accounts} do
      today = Date.utc_today()
      ar = accounts["1100"]
      sales = accounts["4000"]
      cogs = accounts["5000"]
      wip = accounts["1220"]

      # Record revenue: Dr AR, Cr Sales
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "order_delivered", reference: "Rev", description: "Revenue"},
          [
            %{account_id: ar.id, debit_cents: 10000, credit_cents: 0, description: "AR"},
            %{account_id: sales.id, debit_cents: 0, credit_cents: 10000, description: "Sales"}
          ]
        )

      # Record COGS: Dr COGS, Cr WIP
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "order_delivered", reference: "COGS", description: "COGS"},
          [
            %{account_id: cogs.id, debit_cents: 4000, credit_cents: 0, description: "COGS"},
            %{account_id: wip.id, debit_cents: 0, credit_cents: 4000, description: "WIP"}
          ]
        )

      result = Reporting.financial_analysis(today, today)

      # Gross profit = 10000 - 4000 = 6000, margin = 60%
      assert result.profitability.gross_margin_percent == 60.0
      assert result.raw.revenue_cents == 10000
      assert result.raw.cogs_cents == 4000
    end

    test "uses inventory_value_cents option when provided", %{accounts: _accounts} do
      today = Date.utc_today()
      result = Reporting.financial_analysis(today, today, inventory_value_cents: 50000)

      assert result.raw.inventory_value_cents == 50000
    end

    test "uses delivered_order_count option for bakery metrics", %{accounts: accounts} do
      today = Date.utc_today()
      sales = accounts["4000"]
      ar = accounts["1100"]

      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "order_delivered", reference: "Rev2", description: "Revenue"},
          [
            %{account_id: ar.id, debit_cents: 30000, credit_cents: 0, description: "AR"},
            %{account_id: sales.id, debit_cents: 0, credit_cents: 30000, description: "Sales"}
          ]
        )

      result = Reporting.financial_analysis(today, today, delivered_order_count: 3)

      assert result.bakery.revenue_per_order_cents == 10000
      assert result.raw.delivered_order_count == 3
    end

    test "returns nil bakery metrics when no orders and no opex", %{accounts: _accounts} do
      today = Date.utc_today()
      result = Reporting.financial_analysis(today, today)

      assert is_nil(result.bakery.cash_runway_months)
      assert is_nil(result.bakery.revenue_per_order_cents)
      assert is_nil(result.bakery.gross_profit_per_order_cents)
    end

    test "efficiency section includes required ratio keys", %{accounts: _accounts} do
      today = Date.utc_today()
      result = Reporting.financial_analysis(today, today)

      assert Map.has_key?(result.efficiency, :asset_turnover)
      assert Map.has_key?(result.efficiency, :inventory_turnover)
      assert Map.has_key?(result.efficiency, :days_inventory)
      assert Map.has_key?(result.efficiency, :ar_turnover)
      assert Map.has_key?(result.efficiency, :cash_conversion_cycle)
    end

    test "leverage section includes required ratio keys", %{accounts: _accounts} do
      today = Date.utc_today()
      result = Reporting.financial_analysis(today, today)

      assert Map.has_key?(result.leverage, :assets_to_equity)
      assert Map.has_key?(result.leverage, :debt_to_equity)
    end

    test "liquidity section includes required ratio keys", %{accounts: _accounts} do
      today = Date.utc_today()
      result = Reporting.financial_analysis(today, today)

      assert Map.has_key?(result.liquidity, :current_ratio)
      assert Map.has_key?(result.liquidity, :quick_ratio)
    end

    test "period_days is correct for multi-day range", %{accounts: _accounts} do
      start_date = ~D[2025-01-01]
      end_date = ~D[2025-01-31]
      result = Reporting.financial_analysis(start_date, end_date)

      assert result.raw.period_days == 31
    end
  end

  describe "dashboard_metrics/2" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 10000})
      location = location_fixture()

      {:ok, accounts: accounts, product: product, variant: variant, location: location}
    end

    test "returns order counts by status", %{variant: variant, location: location} do
      today = Date.utc_today()

      _order1 = order_fixture(%{variant: variant, location: location, status: "new_order"})
      _order2 = order_fixture(%{variant: variant, location: location, status: "delivered"})

      result = DomainReporting.dashboard_metrics(today, today)

      assert result.total_orders == 2
      assert result.delivered_orders == 1
    end

    test "calculates revenue from all non-canceled orders", %{variant: variant, location: location} do
      today = Date.utc_today()

      _order1 = order_fixture(%{variant: variant, location: location, status: "delivered"})
      _order2 = order_fixture(%{variant: variant, location: location, status: "new_order"})

      result = DomainReporting.dashboard_metrics(today, today)

      # Both orders count for revenue (all non-canceled)
      assert result.revenue_cents == variant.price_cents * 2
    end

    test "groups orders by product", %{location: location} do
      today = Date.utc_today()

      product1 = product_fixture(%{name: "Product A"})
      variant1 = variant_fixture(%{product: product1, price_cents: 10000})
      product2 = product_fixture(%{name: "Product B"})
      variant2 = variant_fixture(%{product: product2, price_cents: 20000})

      _order1 = order_fixture(%{variant: variant1, location: location, status: "delivered"})
      _order2 = order_fixture(%{variant: variant1, location: location, status: "delivered"})
      _order3 = order_fixture(%{variant: variant2, location: location, status: "delivered"})

      result = DomainReporting.dashboard_metrics(today, today)

      assert length(result.orders_by_product) == 2

      product1_stats = Enum.find(result.orders_by_product, fn p -> p.product_id == product1.id end)
      assert product1_stats.order_count == 2
      assert product1_stats.revenue_cents == 20000

      product2_stats = Enum.find(result.orders_by_product, fn p -> p.product_id == product2.id end)
      assert product2_stats.order_count == 1
      assert product2_stats.revenue_cents == 20000
    end

    test "filters by date range", %{variant: variant, location: location} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      _yesterday_order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: yesterday})
      _today_order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})

      # Query only today
      result = DomainReporting.dashboard_metrics(today, today)
      assert result.total_orders == 1
      assert result.delivered_orders == 1

      # Query both days
      result_both = DomainReporting.dashboard_metrics(yesterday, today)
      assert result_both.total_orders == 2
    end

    test "calculates average order value", %{variant: variant, location: location} do
      today = Date.utc_today()

      _order1 = order_fixture(%{variant: variant, location: location, status: "delivered"})
      _order2 = order_fixture(%{variant: variant, location: location, status: "delivered"})

      result = DomainReporting.dashboard_metrics(today, today)

      assert result.delivered_orders == 2
      assert result.avg_order_value_cents == variant.price_cents
    end

    test "calculates avg order value from all non-canceled orders", %{variant: variant, location: location} do
      today = Date.utc_today()

      _order = order_fixture(%{variant: variant, location: location, status: "new_order"})

      result = DomainReporting.dashboard_metrics(today, today)

      # avg_order_value is based on all non-canceled orders
      assert result.delivered_orders == 0
      assert result.total_orders == 1
      assert result.avg_order_value_cents == variant.price_cents
    end
  end

  # ---------------------------------------------------------------------------
  # AR aging report
  # ---------------------------------------------------------------------------

  describe "ar_aging_report/1" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 10000})
      location = location_fixture()

      {:ok, accounts: accounts, variant: variant, location: location}
    end

    test "returns empty result when no delivered orders exist" do
      today = Date.utc_today()
      result = DomainReporting.ar_aging_report(today)

      assert result.as_of_date == today
      assert result.total_outstanding_cents == 0
      assert result.line_items == []
      assert result.buckets == %{current: 0, days_31_60: 0, days_61_90: 0, over_90: 0}
    end

    test "includes unpaid delivered order in current bucket when as_of_date equals delivery_date",
         %{variant: variant, location: location} do
      today = Date.utc_today()
      order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})

      result = DomainReporting.ar_aging_report(today)

      assert result.total_outstanding_cents == 10000
      assert result.buckets.current == 10000
      assert length(result.line_items) == 1

      item = hd(result.line_items)
      assert item.order_id == order.id
      assert item.outstanding_cents == 10000
      assert item.paid_cents == 0
      assert item.order_total_cents == 10000
      assert item.bucket == "current"
      assert item.days_outstanding == 0
    end

    test "excludes fully paid delivered order from line items",
         %{accounts: accounts, variant: variant, location: location} do
      today = Date.utc_today()
      order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})
      _payment = order_payment_fixture(order, accounts["1000"], %{"amount_cents" => 10000})

      result = DomainReporting.ar_aging_report(today)

      assert result.total_outstanding_cents == 0
      assert result.line_items == []
    end

    test "shows outstanding balance for partially paid order",
         %{accounts: accounts, variant: variant, location: location} do
      today = Date.utc_today()
      order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})
      _payment = order_payment_fixture(order, accounts["1000"], %{"amount_cents" => 3000})

      result = DomainReporting.ar_aging_report(today)

      assert result.total_outstanding_cents == 7000

      item = hd(result.line_items)
      assert item.outstanding_cents == 7000
      assert item.paid_cents == 3000
      assert item.order_total_cents == 10000
    end

    test "places orders into correct aging buckets based on days since delivery",
         %{variant: variant, location: location} do
      as_of = Date.utc_today()

      # current: ≤ 30 days — 15 days ago
      _c = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: Date.add(as_of, -15)})
      # 31-60 days — 45 days ago
      _a = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: Date.add(as_of, -45)})
      # 61-90 days — 75 days ago
      _b = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: Date.add(as_of, -75)})
      # 90+ days — 100 days ago
      _d = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: Date.add(as_of, -100)})

      result = DomainReporting.ar_aging_report(as_of)

      assert result.buckets.current == 10000
      assert result.buckets.days_31_60 == 10000
      assert result.buckets.days_61_90 == 10000
      assert result.buckets.over_90 == 10000
      assert result.total_outstanding_cents == 40000
      assert length(result.line_items) == 4
    end

    test "excludes non-delivered orders (new_order, in_prep, canceled)",
         %{variant: variant, location: location} do
      today = Date.utc_today()
      _new = order_fixture(%{variant: variant, location: location, status: "new_order", delivery_date: today})
      _in_prep = order_fixture(%{variant: variant, location: location, status: "in_prep", delivery_date: today})
      _canceled = order_fixture(%{variant: variant, location: location, status: "canceled", delivery_date: today})

      result = DomainReporting.ar_aging_report(today)

      assert result.line_items == []
      assert result.total_outstanding_cents == 0
    end

    test "uses actual_delivery_date over delivery_date for aging calculation",
         %{variant: variant, location: location} do
      as_of = Date.utc_today()
      # delivery_date alone would put this in "current" (5 days ago)
      delivery_date = Date.add(as_of, -5)
      # but actual_delivery_date pushes it into "31-60" (45 days ago)
      actual_delivery_date = Date.add(as_of, -45)

      _order = order_fixture(%{
        variant: variant,
        location: location,
        status: "delivered",
        delivery_date: delivery_date,
        actual_delivery_date: actual_delivery_date
      })

      result = DomainReporting.ar_aging_report(as_of)

      # Should use actual_delivery_date — 45 days → "31-60" bucket
      assert result.buckets.current == 0
      assert result.buckets.days_31_60 == 10000

      item = hd(result.line_items)
      assert item.days_outstanding == 45
      assert item.bucket == "31-60"
    end
  end
end
