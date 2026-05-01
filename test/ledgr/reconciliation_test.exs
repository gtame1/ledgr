defmodule Ledgr.Core.ReconciliationTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.{Reconciliation, Accounting}
  alias Ledgr.Domains.MrMunchMe.Reconciliation, as: InventoryReconciliation
  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Repo
  alias Ledgr.Domains.MrMunchMe.Inventory.{Ingredient, Location}

  import Ledgr.Core.AccountingFixtures

  describe "get_account_balance/2" do
    setup do
      accounts = standard_accounts_fixture()
      {:ok, accounts: accounts}
    end

    test "returns zero for account with no transactions", %{accounts: accounts} do
      cash = accounts["1000"]
      balance = Reconciliation.get_account_balance(cash.id)
      assert balance == 0
    end

    test "returns correct balance for debit account with transactions", %{accounts: accounts} do
      cash = accounts["1000"]
      ar = accounts["1100"]
      today = Date.utc_today()

      # Create a transaction: Cash increased by 10000
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "other", reference: "TEST-1", description: "Test"},
          [
            %{account_id: cash.id, debit_cents: 10000, credit_cents: 0, description: "Cash in"},
            %{account_id: ar.id, debit_cents: 0, credit_cents: 10000, description: "AR out"}
          ]
        )

      balance = Reconciliation.get_account_balance(cash.id, today)
      # Cash is a debit account, so debit - credit = 10000 - 0 = 10000
      assert balance == 10000
    end

    test "respects as_of_date filter", %{accounts: accounts} do
      cash = accounts["1000"]
      ar = accounts["1100"]
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      # Create a transaction today
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "other", reference: "TEST-2", description: "Today"},
          [
            %{account_id: cash.id, debit_cents: 5000, credit_cents: 0, description: "Cash"},
            %{account_id: ar.id, debit_cents: 0, credit_cents: 5000, description: "AR"}
          ]
        )

      # Balance as of yesterday should be 0
      balance_yesterday = Reconciliation.get_account_balance(cash.id, yesterday)
      assert balance_yesterday == 0

      # Balance as of today should be 5000
      balance_today = Reconciliation.get_account_balance(cash.id, today)
      assert balance_today == 5000
    end
  end

  describe "list_accounts_for_reconciliation/1" do
    setup do
      accounts = standard_accounts_fixture()
      {:ok, accounts: accounts}
    end

    test "returns asset and liability accounts", %{accounts: _accounts} do
      result = Reconciliation.list_accounts_for_reconciliation()

      assert is_list(result)
      # All returned accounts should be asset or liability type
      assert Enum.all?(result, fn item ->
               item.account.type in ["asset", "liability"]
             end)
    end

    test "includes balance information", %{accounts: accounts} do
      cash = accounts["1000"]
      ar = accounts["1100"]
      today = LedgrWeb.Helpers.DomainHelpers.today_mx()

      # Create a transaction
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "other", reference: "TEST-3", description: "Test"},
          [
            %{account_id: cash.id, debit_cents: 7500, credit_cents: 0, description: "Cash"},
            %{account_id: ar.id, debit_cents: 0, credit_cents: 7500, description: "AR"}
          ]
        )

      result = Reconciliation.list_accounts_for_reconciliation()
      cash_item = Enum.find(result, fn item -> item.account.id == cash.id end)

      assert cash_item != nil
      assert cash_item.balance_cents == 7500
      assert cash_item.balance_pesos == 75.0
    end
  end

  describe "create_account_reconciliation/4" do
    setup do
      accounts = standard_accounts_fixture()

      # Create the offset account (6099 Other Expenses)
      {:ok, offset} =
        Accounting.create_account(%{
          code: "6099",
          name: "Other Expenses",
          type: "expense",
          normal_balance: "debit",
          is_cash: false
        })

      {:ok, accounts: Map.put(accounts, "6099", offset)}
    end

    test "returns error when no adjustment needed", %{accounts: accounts} do
      cash = accounts["1000"]
      today = Date.utc_today()

      # Balance is 0, actual is 0
      result = Reconciliation.create_account_reconciliation(cash.id, 0, today)

      assert {:error, "No adjustment needed - balances match"} = result
    end

    test "creates adjustment entry for debit account when system is less than actual", %{
      accounts: accounts
    } do
      cash = accounts["1000"]
      today = Date.utc_today()

      # System balance is 0, actual balance is $100
      {:ok, entry} =
        Reconciliation.create_account_reconciliation(cash.id, 100.0, today, "Test adjustment")

      assert entry.entry_type == "reconciliation"

      entry = Repo.preload(entry, :journal_lines)

      # Should have 2 lines
      assert length(entry.journal_lines) == 2

      # Cash should be debited 10000 cents
      cash_line = Enum.find(entry.journal_lines, fn l -> l.account_id == cash.id end)
      assert cash_line.debit_cents == 10000
      assert cash_line.credit_cents == 0

      # Check new balance
      new_balance = Reconciliation.get_account_balance(cash.id, today)
      assert new_balance == 10000
    end

    test "creates adjustment entry for debit account when system is more than actual", %{
      accounts: accounts
    } do
      cash = accounts["1000"]
      ar = accounts["1100"]
      today = Date.utc_today()

      # First add 200 to cash
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{date: today, entry_type: "other", reference: "SETUP", description: "Setup"},
          [
            %{account_id: cash.id, debit_cents: 20000, credit_cents: 0, description: "Cash in"},
            %{account_id: ar.id, debit_cents: 0, credit_cents: 20000, description: "AR out"}
          ]
        )

      # System shows 200, actual is 150 - need to reduce by 50
      {:ok, entry} = Reconciliation.create_account_reconciliation(cash.id, 150.0, today)

      entry = Repo.preload(entry, :journal_lines)

      # Cash should be credited 5000 cents
      cash_line = Enum.find(entry.journal_lines, fn l -> l.account_id == cash.id end)
      assert cash_line.credit_cents == 5000
      assert cash_line.debit_cents == 0

      # Check new balance
      new_balance = Reconciliation.get_account_balance(cash.id, today)
      assert new_balance == 15000
    end
  end

  describe "inventory reconciliation" do
    setup do
      accounts = standard_accounts_fixture()

      # Create waste expense account
      {:ok, _} =
        Accounting.create_account(%{
          code: "6060",
          name: "Inventory Waste",
          type: "expense",
          normal_balance: "debit",
          is_cash: false
        })

      # Create ingredient
      {:ok, ingredient} =
        %Ingredient{}
        |> Ingredient.changeset(%{code: "FLOUR", name: "Flour", unit: "g"})
        |> Repo.insert()

      # Create location
      {:ok, location} =
        %Location{}
        |> Location.changeset(%{code: "WH", name: "Warehouse"})
        |> Repo.insert()

      {:ok, accounts: accounts, ingredient: ingredient, location: location}
    end

    test "get_inventory_quantity/2 returns 0 for no stock", %{
      ingredient: ingredient,
      location: location
    } do
      quantity = InventoryReconciliation.get_inventory_quantity(ingredient.id, location.id)
      assert quantity == 0
    end

    test "get_inventory_quantity/2 returns correct quantity after purchase", %{
      accounts: accounts,
      ingredient: ingredient,
      location: location
    } do
      cash = accounts["1000"]

      # Create a purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 500,
        "total_cost_pesos" => "25.00",
        "paid_from_account_id" => to_string(cash.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      quantity = InventoryReconciliation.get_inventory_quantity(ingredient.id, location.id)
      assert quantity == 500
    end

    test "list_inventory_for_reconciliation/0 returns inventory items", %{
      accounts: accounts,
      ingredient: ingredient,
      location: location
    } do
      cash = accounts["1000"]

      # Create a purchase to have stock
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 300,
        "total_cost_pesos" => "15.00",
        "paid_from_account_id" => to_string(cash.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      result = InventoryReconciliation.list_inventory_for_reconciliation()

      assert is_list(result)
      # Find our ingredient/location combo - the result has :ingredient and :location associations
      item =
        Enum.find(result, fn i ->
          i.ingredient.id == ingredient.id && i.location.id == location.id
        end)

      assert item != nil
      assert item.quantity_on_hand == 300
    end

    test "create_inventory_reconciliation/5 adjusts quantity upward", %{
      accounts: accounts,
      ingredient: ingredient,
      location: location
    } do
      cash = accounts["1000"]

      # Create initial purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 100,
        "total_cost_pesos" => "10.00",
        "paid_from_account_id" => to_string(cash.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      # System shows 100, actual is 150
      {:ok, _} =
        InventoryReconciliation.create_inventory_reconciliation(
          ingredient.id,
          location.id,
          150,
          Date.utc_today(),
          "Found extra stock"
        )

      # Check new quantity
      quantity = InventoryReconciliation.get_inventory_quantity(ingredient.id, location.id)
      assert quantity == 150
    end

    test "create_inventory_reconciliation/5 adjusts quantity downward", %{
      accounts: accounts,
      ingredient: ingredient,
      location: location
    } do
      cash = accounts["1000"]

      # Create initial purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 200,
        "total_cost_pesos" => "20.00",
        "paid_from_account_id" => to_string(cash.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      # System shows 200, actual is 150
      {:ok, _} =
        InventoryReconciliation.create_inventory_reconciliation(
          ingredient.id,
          location.id,
          150,
          Date.utc_today(),
          "Shrinkage adjustment"
        )

      # Check new quantity
      quantity = InventoryReconciliation.get_inventory_quantity(ingredient.id, location.id)
      assert quantity == 150
    end

    test "create_inventory_reconciliation/5 returns error when no adjustment needed", %{
      accounts: accounts,
      ingredient: ingredient,
      location: location
    } do
      cash = accounts["1000"]

      # Create initial purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 100,
        "total_cost_pesos" => "10.00",
        "paid_from_account_id" => to_string(cash.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      # System shows 100, actual is 100
      result =
        InventoryReconciliation.create_inventory_reconciliation(
          ingredient.id,
          location.id,
          100,
          Date.utc_today()
        )

      assert {:error, "No adjustment needed - quantities match"} = result
    end
  end
end
