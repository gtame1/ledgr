defmodule Ledgr.Core.Accounting.InventoryMovementAccountingTest do
  use Ledgr.DataCase, async: true

  import Ecto.Query

  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.MrMunchMe.OrderAccounting
  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Repo
  alias Ledgr.Core.Accounting.{Account, JournalEntry, JournalLine}

  alias Ledgr.Domains.MrMunchMe.Inventory.{
    Ingredient,
    Location,
    InventoryMovement,
    Recipe,
    RecipeLine
  }

  alias Ledgr.Domains.MrMunchMe.Orders.{Order, Product, ProductVariant}

  setup do
    # Create accounts
    {:ok, cash_account} =
      Accounting.create_account(%{
        code: "1000",
        name: "Cash",
        type: "asset",
        normal_balance: "debit",
        is_cash: true
      })

    {:ok, ingredients_account} =
      Accounting.create_account(%{
        code: "1200",
        name: "Ingredients Inventory",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      })

    {:ok, wip_account} =
      Accounting.create_account(%{
        code: "1220",
        name: "Ingredients Inventory (WIP)",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      })

    {:ok, ar_account} =
      Accounting.create_account(%{
        code: "1100",
        name: "Accounts Receivable",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      })

    {:ok, sales_account} =
      Accounting.create_account(%{
        code: "4000",
        name: "Sales",
        type: "revenue",
        normal_balance: "credit",
        is_cash: false
      })

    {:ok, cogs_account} =
      Accounting.create_account(%{
        code: "5000",
        name: "Ingredients COGS",
        type: "expense",
        normal_balance: "debit",
        is_cash: false,
        is_cogs: true
      })

    {:ok, _packing_cogs_account} =
      Accounting.create_account(%{
        code: "5010",
        name: "Packing COGS",
        type: "expense",
        normal_balance: "debit",
        is_cash: false,
        is_cogs: true
      })

    {:ok, _packing_inventory_account} =
      Accounting.create_account(%{
        code: "1210",
        name: "Packing Inventory",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      })

    {:ok, _kitchen_equipment_account} =
      Accounting.create_account(%{
        code: "1300",
        name: "Kitchen Equipment",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      })

    {:ok, _customer_deposits_account} =
      Accounting.create_account(%{
        code: "2200",
        name: "Customer Deposits",
        type: "liability",
        normal_balance: "credit",
        is_cash: false
      })

    # Create ingredients
    {:ok, flour} =
      %Ingredient{}
      |> Ingredient.changeset(%{
        code: "FLOUR",
        name: "Flour",
        unit: "g",
        cost_per_unit_cents: 5
      })
      |> Repo.insert()

    {:ok, sugar} =
      %Ingredient{}
      |> Ingredient.changeset(%{
        code: "SUGAR",
        name: "Sugar",
        unit: "g",
        cost_per_unit_cents: 3
      })
      |> Repo.insert()

    # Create location
    {:ok, location} =
      %Location{}
      |> Location.changeset(%{
        code: "CASA_AG",
        name: "Casa AG"
      })
      |> Repo.insert()

    # Create product and variant
    {:ok, product} =
      %Product{}
      |> Product.changeset(%{
        name: "Cookie",
        active: true
      })
      |> Repo.insert()

    {:ok, variant} =
      %ProductVariant{}
      |> ProductVariant.changeset(%{
        name: "Standard",
        sku: "COOKIE",
        price_cents: 1000,
        active: true,
        product_id: product.id
      })
      |> Repo.insert()

    # Create recipe
    {:ok, recipe} =
      %Recipe{}
      |> Recipe.changeset(%{
        variant_id: variant.id,
        effective_date: Date.utc_today(),
        name: "Cookie Recipe",
        description: "Basic cookie recipe"
      })
      |> Repo.insert()

    # Create recipe lines
    {:ok, _recipe_line1} =
      %RecipeLine{}
      |> RecipeLine.changeset(%{
        ingredient_code: "FLOUR",
        quantity: Decimal.new("200")
      })
      |> Ecto.Changeset.put_change(:recipe_id, recipe.id)
      |> Repo.insert()

    {:ok, _recipe_line2} =
      %RecipeLine{}
      |> RecipeLine.changeset(%{
        ingredient_code: "SUGAR",
        quantity: Decimal.new("100")
      })
      |> Ecto.Changeset.put_change(:recipe_id, recipe.id)
      |> Repo.insert()

    # Purchase ingredients to have stock
    purchase_attrs1 = %{
      "ingredient_code" => "FLOUR",
      "location_code" => "CASA_AG",
      "quantity" => 10000,
      # 50,000 cents / 10,000 = 5 cents per gram
      "total_cost_pesos" => "500.00",
      "paid_from_account_id" => to_string(cash_account.id),
      "purchase_date" => Date.utc_today()
    }

    {:ok, _} = Inventory.create_purchase(purchase_attrs1)

    purchase_attrs2 = %{
      "ingredient_code" => "SUGAR",
      "location_code" => "CASA_AG",
      "quantity" => 5000,
      # 15,000 cents / 5,000 = 3 cents per gram
      "total_cost_pesos" => "150.00",
      "paid_from_account_id" => to_string(cash_account.id),
      "purchase_date" => Date.utc_today()
    }

    {:ok, _} = Inventory.create_purchase(purchase_attrs2)

    {
      :ok,
      cash_account: cash_account,
      ingredients_account: ingredients_account,
      wip_account: wip_account,
      ar_account: ar_account,
      sales_account: sales_account,
      cogs_account: cogs_account,
      flour: flour,
      sugar: sugar,
      location: location,
      product: product,
      variant: variant
    }
  end

  describe "order_in_prep accounting" do
    test "creates balanced journal entry when order moves to in_prep", %{
      wip_account: wip_account,
      variant: variant,
      location: location
    } do
      # Get ingredients account from setup
      ingredients_account = Accounting.get_account_by_code!("1200")

      # Create order
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test Customer",
          customer_email: "test@example.com",
          customer_phone: "1234567890",
          variant_id: variant.id,
          delivery_date: Date.utc_today(),
          delivery_type: "delivery",
          status: "new_order",
          prep_location_id: location.id
        })
        |> Repo.insert()

      # Move order to in_prep
      OrderAccounting.handle_order_status_change(order, "in_prep")

      # Verify journal entry was created
      reference = "Order ##{order.id}"

      journal_entry =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "order_in_prep" and je.reference == ^reference,
            preload: :journal_lines
        )

      assert journal_entry != nil
      assert journal_entry.entry_type == "order_in_prep"
      assert journal_entry.reference == "Order ##{order.id}"

      # Verify journal entry is balanced (debits = credits)
      total_debits =
        journal_entry.journal_lines
        |> Enum.map(& &1.debit_cents)
        |> Enum.sum()

      total_credits =
        journal_entry.journal_lines
        |> Enum.map(& &1.credit_cents)
        |> Enum.sum()

      assert total_debits == total_credits

      # Verify WIP debit
      wip_line =
        Enum.find(journal_entry.journal_lines, fn line ->
          line.account_id == wip_account.id && line.debit_cents > 0
        end)

      assert wip_line != nil
      wip_debit = wip_line.debit_cents
      assert wip_debit > 0

      # Verify Ingredients Inventory credit
      ingredients_line =
        Enum.find(journal_entry.journal_lines, fn line ->
          line.account_id == ingredients_account.id && line.credit_cents > 0
        end)

      assert ingredients_line != nil
      ingredients_credit = ingredients_line.credit_cents
      assert ingredients_credit > 0

      # Verify WIP debit equals Ingredients Inventory credit
      assert wip_debit == ingredients_credit,
             "WIP debit (#{wip_debit}) should equal Ingredients Inventory credit (#{ingredients_credit})"
    end

    test "journal entry amount matches inventory movement costs", %{
      wip_account: wip_account,
      variant: variant,
      location: location,
      flour: flour,
      sugar: sugar
    } do
      # Create order
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test Customer",
          customer_email: "test@example.com",
          customer_phone: "1234567890",
          variant_id: variant.id,
          delivery_date: Date.utc_today(),
          delivery_type: "delivery",
          status: "new_order",
          prep_location_id: location.id
        })
        |> Repo.insert()

      # Calculate expected cost:
      # Recipe: 200g FLOUR @ 5 cents/g = 1000 cents
      #         100g SUGAR @ 3 cents/g = 300 cents
      # Total: 1300 cents
      expected_cost = 200 * 5 + 100 * 3

      # Move order to in_prep
      OrderAccounting.handle_order_status_change(order, "in_prep")

      # Get journal entry
      reference = "Order ##{order.id}"

      journal_entry =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "order_in_prep" and je.reference == ^reference,
            preload: :journal_lines
        )

      # Get WIP debit amount
      wip_debit =
        journal_entry.journal_lines
        |> Enum.find(fn line -> line.account_id == wip_account.id && line.debit_cents > 0 end)
        |> Map.get(:debit_cents)

      # Verify journal entry amount matches expected cost
      assert wip_debit == expected_cost,
             "Journal entry WIP debit (#{wip_debit}) should match expected cost (#{expected_cost})"

      # Verify inventory movements were created with correct costs
      flour_movement =
        Repo.one(
          from m in InventoryMovement,
            where:
              m.ingredient_id == ^flour.id and m.source_type == "order" and
                m.source_id == ^order.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      sugar_movement =
        Repo.one(
          from m in InventoryMovement,
            where:
              m.ingredient_id == ^sugar.id and m.source_type == "order" and
                m.source_id == ^order.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      assert flour_movement != nil
      assert sugar_movement != nil

      # Verify movement costs match expected
      assert flour_movement.total_cost_cents == 200 * 5
      assert sugar_movement.total_cost_cents == 100 * 3

      # Verify sum of movement costs equals journal entry amount
      total_movement_cost = flour_movement.total_cost_cents + sugar_movement.total_cost_cents

      assert total_movement_cost == wip_debit,
             "Total movement cost (#{total_movement_cost}) should equal journal entry amount (#{wip_debit})"
    end

    test "account balances are updated correctly after in_prep", %{
      wip_account: wip_account,
      variant: variant,
      location: location
    } do
      # Get ingredients account from setup
      ingredients_account = Accounting.get_account_by_code!("1200")

      # Get initial balances
      initial_ingredients_balance = get_account_balance(ingredients_account.id)
      initial_wip_balance = get_account_balance(wip_account.id)

      # Create order
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test Customer",
          customer_email: "test@example.com",
          customer_phone: "1234567890",
          variant_id: variant.id,
          delivery_date: Date.utc_today(),
          delivery_type: "delivery",
          status: "new_order",
          prep_location_id: location.id
        })
        |> Repo.insert()

      # Move order to in_prep
      OrderAccounting.handle_order_status_change(order, "in_prep")

      # Get journal entry to find the amount
      reference = "Order ##{order.id}"

      journal_entry =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "order_in_prep" and je.reference == ^reference,
            preload: :journal_lines
        )

      wip_debit =
        journal_entry.journal_lines
        |> Enum.find(fn line -> line.account_id == wip_account.id && line.debit_cents > 0 end)
        |> Map.get(:debit_cents)

      # Verify account balances
      new_ingredients_balance = get_account_balance(ingredients_account.id)
      new_wip_balance = get_account_balance(wip_account.id)

      # Ingredients Inventory should decrease (credit)
      assert new_ingredients_balance == initial_ingredients_balance - wip_debit,
             "Ingredients Inventory should decrease by #{wip_debit}"

      # WIP should increase (debit)
      assert new_wip_balance == initial_wip_balance + wip_debit,
             "WIP should increase by #{wip_debit}"
    end
  end

  describe "order_delivered accounting" do
    test "creates balanced journal entries when order is delivered", %{
      wip_account: wip_account,
      ar_account: ar_account,
      sales_account: sales_account,
      cogs_account: cogs_account,
      variant: variant,
      location: location
    } do
      # Create order and move to in_prep first
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test Customer",
          customer_email: "test@example.com",
          customer_phone: "1234567890",
          variant_id: variant.id,
          delivery_date: Date.utc_today(),
          delivery_type: "delivery",
          status: "new_order",
          prep_location_id: location.id
        })
        |> Repo.insert()

      OrderAccounting.handle_order_status_change(order, "in_prep")

      # Get the WIP debit amount from in_prep entry
      reference = "Order ##{order.id}"

      in_prep_entry =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "order_in_prep" and je.reference == ^reference,
            preload: :journal_lines
        )

      wip_debit_from_in_prep =
        in_prep_entry.journal_lines
        |> Enum.find(fn line -> line.account_id == wip_account.id && line.debit_cents > 0 end)
        |> Map.get(:debit_cents)

      # Move order to delivered
      OrderAccounting.handle_order_status_change(order, "delivered")

      # Verify delivered journal entry was created
      reference = "Order ##{order.id}"

      delivered_entry =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "order_delivered" and je.reference == ^reference,
            preload: :journal_lines
        )

      assert delivered_entry != nil

      # Verify journal entry is balanced
      total_debits =
        delivered_entry.journal_lines
        |> Enum.map(& &1.debit_cents)
        |> Enum.sum()

      total_credits =
        delivered_entry.journal_lines
        |> Enum.map(& &1.credit_cents)
        |> Enum.sum()

      assert total_debits == total_credits

      # Verify revenue lines (AR debit, Sales credit)
      ar_line =
        Enum.find(delivered_entry.journal_lines, fn line ->
          line.account_id == ar_account.id && line.debit_cents > 0
        end)

      sales_line =
        Enum.find(delivered_entry.journal_lines, fn line ->
          line.account_id == sales_account.id && line.credit_cents > 0
        end)

      assert ar_line != nil
      assert sales_line != nil
      assert ar_line.debit_cents == sales_line.credit_cents

      # Verify COGS lines (COGS debit, WIP credit)
      cogs_line =
        Enum.find(delivered_entry.journal_lines, fn line ->
          line.account_id == cogs_account.id && line.debit_cents > 0
        end)

      wip_credit_line =
        Enum.find(delivered_entry.journal_lines, fn line ->
          line.account_id == wip_account.id && line.credit_cents > 0
        end)

      assert cogs_line != nil
      assert wip_credit_line != nil
      assert cogs_line.debit_cents == wip_credit_line.credit_cents

      # Verify WIP credit equals original WIP debit
      assert wip_credit_line.credit_cents == wip_debit_from_in_prep,
             "WIP credit (#{wip_credit_line.credit_cents}) should equal original WIP debit (#{wip_debit_from_in_prep})"

      # Verify COGS debit equals WIP credit
      assert cogs_line.debit_cents == wip_credit_line.credit_cents,
             "COGS debit (#{cogs_line.debit_cents}) should equal WIP credit (#{wip_credit_line.credit_cents})"
    end

    test "account balances are updated correctly after delivery", %{
      wip_account: wip_account,
      cogs_account: cogs_account,
      ar_account: ar_account,
      sales_account: sales_account,
      variant: variant,
      location: location
    } do
      # Create order and move to in_prep
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test Customer",
          customer_email: "test@example.com",
          customer_phone: "1234567890",
          variant_id: variant.id,
          delivery_date: Date.utc_today(),
          delivery_type: "delivery",
          status: "new_order",
          prep_location_id: location.id
        })
        |> Repo.insert()

      OrderAccounting.handle_order_status_change(order, "in_prep")

      # Get balances after in_prep
      wip_balance_after_in_prep = get_account_balance(wip_account.id)

      # Move order to delivered
      OrderAccounting.handle_order_status_change(order, "delivered")

      # Get balances after delivery
      wip_balance_after_delivery = get_account_balance(wip_account.id)
      cogs_balance_after_delivery = get_account_balance(cogs_account.id)
      ar_balance_after_delivery = get_account_balance(ar_account.id)
      sales_balance_after_delivery = get_account_balance(sales_account.id)

      # WIP should be relieved (credit), so balance should decrease
      assert wip_balance_after_delivery < wip_balance_after_in_prep,
             "WIP balance should decrease after delivery"

      # COGS should increase (debit)
      assert cogs_balance_after_delivery > 0,
             "COGS balance should increase after delivery"

      # AR should increase (debit)
      assert ar_balance_after_delivery > 0,
             "AR balance should increase after delivery"

      # Sales should increase (credit)
      assert sales_balance_after_delivery > 0,
             "Sales balance should increase after delivery"

      # Verify WIP was fully relieved
      wip_relieved = wip_balance_after_in_prep - wip_balance_after_delivery

      assert wip_relieved == wip_balance_after_in_prep,
             "WIP should be fully relieved. Balance before: #{wip_balance_after_in_prep}, after: #{wip_balance_after_delivery}"
    end
  end

  describe "end-to-end order flow" do
    test "complete order flow maintains accounting accuracy", %{
      wip_account: wip_account,
      cogs_account: cogs_account,
      ar_account: ar_account,
      sales_account: sales_account,
      variant: variant,
      location: location
    } do
      # Get ingredients account from setup
      ingredients_account = Accounting.get_account_by_code!("1200")

      # Get initial balances
      initial_ingredients_balance = get_account_balance(ingredients_account.id)
      initial_wip_balance = get_account_balance(wip_account.id)
      initial_cogs_balance = get_account_balance(cogs_account.id)
      initial_ar_balance = get_account_balance(ar_account.id)
      initial_sales_balance = get_account_balance(sales_account.id)

      # Create order
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test Customer",
          customer_email: "test@example.com",
          customer_phone: "1234567890",
          variant_id: variant.id,
          delivery_date: Date.utc_today(),
          delivery_type: "delivery",
          status: "new_order",
          prep_location_id: location.id
        })
        |> Repo.insert()

      # Move to in_prep
      OrderAccounting.handle_order_status_change(order, "in_prep")

      # Get WIP debit amount
      reference = "Order ##{order.id}"

      in_prep_entry =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "order_in_prep" and je.reference == ^reference,
            preload: :journal_lines
        )

      wip_debit =
        in_prep_entry.journal_lines
        |> Enum.find(fn line -> line.account_id == wip_account.id && line.debit_cents > 0 end)
        |> Map.get(:debit_cents)

      # Verify balances after in_prep
      ingredients_balance_after_in_prep = get_account_balance(ingredients_account.id)
      wip_balance_after_in_prep = get_account_balance(wip_account.id)

      assert ingredients_balance_after_in_prep == initial_ingredients_balance - wip_debit
      assert wip_balance_after_in_prep == initial_wip_balance + wip_debit

      # Move to delivered
      OrderAccounting.handle_order_status_change(order, "delivered")

      # Get delivered entry amounts
      reference = "Order ##{order.id}"

      delivered_entry =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "order_delivered" and je.reference == ^reference,
            preload: :journal_lines
        )

      revenue_amount =
        delivered_entry.journal_lines
        |> Enum.find(fn line -> line.account_id == ar_account.id && line.debit_cents > 0 end)
        |> Map.get(:debit_cents)

      cogs_amount =
        delivered_entry.journal_lines
        |> Enum.find(fn line -> line.account_id == cogs_account.id && line.debit_cents > 0 end)
        |> Map.get(:debit_cents)

      # Verify final balances
      final_ingredients_balance = get_account_balance(ingredients_account.id)
      final_wip_balance = get_account_balance(wip_account.id)
      final_cogs_balance = get_account_balance(cogs_account.id)
      final_ar_balance = get_account_balance(ar_account.id)
      final_sales_balance = get_account_balance(sales_account.id)

      # Ingredients Inventory: decreased by wip_debit (unchanged from in_prep)
      assert final_ingredients_balance == initial_ingredients_balance - wip_debit

      # WIP: increased by wip_debit, then decreased by wip_debit (back to initial)
      assert final_wip_balance == initial_wip_balance,
             "WIP should return to initial balance after delivery. Initial: #{initial_wip_balance}, Final: #{final_wip_balance}"

      # COGS: increased by cogs_amount
      assert final_cogs_balance == initial_cogs_balance + cogs_amount

      # AR: increased by revenue_amount
      assert final_ar_balance == initial_ar_balance + revenue_amount

      # Sales: increased by revenue_amount (credit, so balance increases)
      assert final_sales_balance == initial_sales_balance + revenue_amount

      # Verify COGS equals WIP debit
      assert cogs_amount == wip_debit,
             "COGS amount (#{cogs_amount}) should equal WIP debit (#{wip_debit})"
    end
  end

  describe "duplicate entry prevention" do
    test "calling handle_order_status_change('in_prep') twice creates only one entry", %{
      variant: variant,
      location: location
    } do
      # Create order
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test Customer",
          customer_email: "test@example.com",
          customer_phone: "1234567890",
          variant_id: variant.id,
          delivery_date: Date.utc_today(),
          delivery_type: "delivery",
          status: "new_order",
          prep_location_id: location.id
        })
        |> Repo.insert()

      # Call in_prep TWICE
      OrderAccounting.handle_order_status_change(order, "in_prep")
      OrderAccounting.handle_order_status_change(order, "in_prep")

      # Verify only ONE journal entry exists
      reference = "Order ##{order.id}"

      entries =
        from(je in JournalEntry,
          where: je.entry_type == "order_in_prep" and je.reference == ^reference
        )
        |> Repo.all()

      assert length(entries) == 1, "Expected 1 order_in_prep entry, got #{length(entries)}"
    end

    test "calling handle_order_status_change('delivered') twice creates only one entry", %{
      variant: variant,
      location: location
    } do
      # Create order
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test Customer",
          customer_email: "test@example.com",
          customer_phone: "1234567890",
          variant_id: variant.id,
          delivery_date: Date.utc_today(),
          delivery_type: "delivery",
          status: "new_order",
          prep_location_id: location.id
        })
        |> Repo.insert()

      # Move to in_prep first
      OrderAccounting.handle_order_status_change(order, "in_prep")

      # Call delivered TWICE
      OrderAccounting.handle_order_status_change(order, "delivered")
      OrderAccounting.handle_order_status_change(order, "delivered")

      # Verify only ONE journal entry exists
      reference = "Order ##{order.id}"

      entries =
        from(je in JournalEntry,
          where: je.entry_type == "order_delivered" and je.reference == ^reference
        )
        |> Repo.all()

      assert length(entries) == 1, "Expected 1 order_delivered entry, got #{length(entries)}"
    end

    test "COGS is not duplicated even with multiple status transitions", %{
      wip_account: wip_account,
      cogs_account: cogs_account,
      variant: variant,
      location: location
    } do
      # Create order
      {:ok, order} =
        %Order{}
        |> Order.changeset(%{
          customer_name: "Test Customer",
          customer_email: "test@example.com",
          customer_phone: "1234567890",
          variant_id: variant.id,
          delivery_date: Date.utc_today(),
          delivery_type: "delivery",
          status: "new_order",
          prep_location_id: location.id
        })
        |> Repo.insert()

      # Move to in_prep multiple times
      OrderAccounting.handle_order_status_change(order, "in_prep")
      OrderAccounting.handle_order_status_change(order, "in_prep")
      OrderAccounting.handle_order_status_change(order, "in_prep")

      # Get expected WIP/COGS from the single in_prep entry
      reference = "Order ##{order.id}"

      in_prep_entry =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "order_in_prep" and je.reference == ^reference,
            preload: :journal_lines
        )

      expected_cogs =
        in_prep_entry.journal_lines
        |> Enum.find(fn line -> line.account_id == wip_account.id && line.debit_cents > 0 end)
        |> Map.get(:debit_cents)

      # Deliver multiple times
      OrderAccounting.handle_order_status_change(order, "delivered")
      OrderAccounting.handle_order_status_change(order, "delivered")
      OrderAccounting.handle_order_status_change(order, "delivered")

      # Get actual COGS balance
      actual_cogs = get_account_balance(cogs_account.id)

      assert actual_cogs == expected_cogs,
             "COGS should be #{expected_cogs} but was #{actual_cogs} (possible duplication)"
    end
  end

  # Helper function to get account balance
  defp get_account_balance(account_id) do
    result =
      from(jl in JournalLine,
        where: jl.account_id == ^account_id,
        select: %{
          total_debits: fragment("COALESCE(SUM(?), 0)", jl.debit_cents),
          total_credits: fragment("COALESCE(SUM(?), 0)", jl.credit_cents)
        }
      )
      |> Repo.one()

    total_debits =
      case result do
        %{total_debits: debits} when is_integer(debits) -> debits
        %{total_debits: %Decimal{} = debits} -> Decimal.to_integer(debits)
        _ -> 0
      end

    total_credits =
      case result do
        %{total_credits: credits} when is_integer(credits) -> credits
        %{total_credits: %Decimal{} = credits} -> Decimal.to_integer(credits)
        _ -> 0
      end

    # For asset accounts, balance = debits - credits
    # For liability/equity/revenue accounts, balance = credits - debits
    account = Repo.get!(Account, account_id)

    case account.type do
      "asset" -> total_debits - total_credits
      "expense" -> total_debits - total_credits
      _ -> total_credits - total_debits
    end
  end
end
