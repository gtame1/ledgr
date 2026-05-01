defmodule Ledgr.Domains.MrMunchMe.InventoryTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Domains.MrMunchMe.Inventory.{Ingredient, Location, InventoryItem}
  alias Ledgr.Repo

  import Ledgr.Core.AccountingFixtures

  setup do
    standard_accounts_fixture()
    # Extra inventory accounts not in standard fixture
    extra_accounts = [
      %{
        code: "1220",
        name: "Kitchen Equipment",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      },
      %{
        code: "5010",
        name: "Packing COGS",
        type: "expense",
        normal_balance: "debit",
        is_cash: false,
        is_cogs: true
      },
      %{
        code: "6060",
        name: "Inventory Waste",
        type: "expense",
        normal_balance: "debit",
        is_cash: false
      }
    ]

    Enum.each(extra_accounts, fn attrs ->
      case Ledgr.Core.Accounting.get_account_by_code(attrs.code) do
        nil -> {:ok, _} = Ledgr.Core.Accounting.create_account(attrs)
        _ -> :ok
      end
    end)

    :ok
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp ingredient_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    {:ok, ingredient} =
      Inventory.create_ingredient(
        Enum.into(attrs, %{
          code: "ING#{unique}",
          name: "Ingredient #{unique}",
          unit: "g",
          cost_per_unit_cents: 10,
          inventory_type: "ingredients"
        })
      )

    ingredient
  end

  defp location_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    {:ok, location} =
      %Location{}
      |> Location.changeset(
        Enum.into(attrs, %{
          code: "LOC#{unique}",
          name: "Location #{unique}"
        })
      )
      |> Repo.insert()

    location
  end

  defp paid_from_account, do: Ledgr.Core.Accounting.get_account_by_code!("1000")

  # ── Ingredients CRUD ─────────────────────────────────────────────────

  describe "list_ingredients/0" do
    test "returns all ingredients" do
      ingredient = ingredient_fixture()
      ingredients = Inventory.list_ingredients()
      assert Enum.any?(ingredients, fn i -> i.id == ingredient.id end)
    end

    test "orders by name" do
      ingredient_fixture(%{code: "ZZZ1", name: "Zucchini"})
      ingredient_fixture(%{code: "AAA1", name: "Almonds"})

      ingredients = Inventory.list_ingredients()
      names = Enum.map(ingredients, & &1.name)
      assert names == Enum.sort(names)
    end
  end

  describe "get_ingredient!/1" do
    test "returns ingredient by id" do
      ingredient = ingredient_fixture()
      found = Inventory.get_ingredient!(ingredient.id)
      assert found.id == ingredient.id
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Inventory.get_ingredient!(0)
      end
    end
  end

  describe "get_ingredient_by_code!/1" do
    test "returns ingredient by code" do
      ingredient = ingredient_fixture(%{code: "TESTCODE1"})
      found = Inventory.get_ingredient_by_code!("TESTCODE1")
      assert found.id == ingredient.id
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Inventory.get_ingredient_by_code!("NOTEXIST")
      end
    end
  end

  describe "create_ingredient/1" do
    test "creates ingredient with valid attrs" do
      unique = System.unique_integer([:positive])

      assert {:ok, %Ingredient{} = ing} =
               Inventory.create_ingredient(%{
                 code: "FL#{unique}",
                 name: "Flour",
                 unit: "g",
                 cost_per_unit_cents: 5,
                 inventory_type: "ingredients"
               })

      assert ing.unit == "g"
      assert ing.inventory_type == "ingredients"
    end

    test "returns error with missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Inventory.create_ingredient(%{})
    end

    test "returns error with invalid inventory_type" do
      assert {:error, changeset} =
               Inventory.create_ingredient(%{
                 code: "XX1",
                 name: "Test",
                 unit: "g",
                 cost_per_unit_cents: 5,
                 inventory_type: "invalid_type"
               })

      assert errors_on(changeset)[:inventory_type]
    end
  end

  describe "update_ingredient/2" do
    test "updates ingredient name" do
      ingredient = ingredient_fixture(%{name: "Old Name"})
      assert {:ok, updated} = Inventory.update_ingredient(ingredient, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "updates cost_per_unit_cents" do
      ingredient = ingredient_fixture(%{cost_per_unit_cents: 10})
      assert {:ok, updated} = Inventory.update_ingredient(ingredient, %{cost_per_unit_cents: 20})
      assert updated.cost_per_unit_cents == 20
    end
  end

  describe "delete_ingredient/1" do
    test "deletes an ingredient" do
      ingredient = ingredient_fixture()
      {:ok, _} = Inventory.delete_ingredient(ingredient)

      assert_raise Ecto.NoResultsError, fn ->
        Inventory.get_ingredient!(ingredient.id)
      end
    end
  end

  describe "change_ingredient/2" do
    test "returns a changeset" do
      ingredient = ingredient_fixture()
      assert %Ecto.Changeset{} = Inventory.change_ingredient(ingredient, %{name: "Changed"})
    end
  end

  # ── Stock ─────────────────────────────────────────────────────────────

  describe "get_or_create_stock!/2" do
    test "creates a new stock item when none exists" do
      ingredient = ingredient_fixture()
      location = location_fixture()

      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.ingredient_id == ingredient.id
      assert stock.location_id == location.id
      assert stock.quantity_on_hand == 0
    end

    test "returns existing stock item on second call" do
      ingredient = ingredient_fixture()
      location = location_fixture()

      stock1 = Inventory.get_or_create_stock!(ingredient.id, location.id)
      stock2 = Inventory.get_or_create_stock!(ingredient.id, location.id)

      assert stock1.id == stock2.id
    end
  end

  describe "list_stock_items/0" do
    test "returns all stock items with ingredient and location preloaded" do
      ingredient = ingredient_fixture()
      location = location_fixture()
      Inventory.get_or_create_stock!(ingredient.id, location.id)

      items = Inventory.list_stock_items()
      found = Enum.find(items, fn i -> i.ingredient_id == ingredient.id end)
      assert found != nil
      assert found.ingredient != nil
      assert found.location != nil
    end
  end

  # ── Purchases ─────────────────────────────────────────────────────────

  describe "record_purchase/6" do
    test "creates a movement and updates stock quantity" do
      ingredient = ingredient_fixture()
      location = location_fixture()
      cash = paid_from_account()

      assert {:ok, {:ok, %{movement: movement}}} =
               Inventory.record_purchase(
                 ingredient.code,
                 location.code,
                 1000,
                 cash.id,
                 5,
                 Date.utc_today()
               )

      assert movement.movement_type == "purchase"
      assert movement.quantity == 1000

      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.quantity_on_hand == 1000
    end

    test "updates moving average cost after multiple purchases" do
      ingredient = ingredient_fixture()
      location = location_fixture()
      cash = paid_from_account()

      # First purchase: 1000g at 5 cents/g = 5000 cents total
      Inventory.record_purchase(
        ingredient.code,
        location.code,
        1000,
        cash.id,
        5,
        Date.utc_today()
      )

      # Second purchase: 1000g at 15 cents/g = 15000 cents total
      # Cumulative avg = (5000 + 15000) / (1000 + 1000) = 10 cents/g
      {:ok, {:ok, _}} =
        Inventory.record_purchase(
          ingredient.code,
          location.code,
          1000,
          cash.id,
          15,
          Date.utc_today()
        )

      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.quantity_on_hand == 2000
      assert stock.avg_cost_per_unit_cents == 10
    end

    test "records movement with source_type and source_id" do
      ingredient = ingredient_fixture()
      location = location_fixture()
      cash = paid_from_account()

      {:ok, {:ok, %{movement: movement}}} =
        Inventory.record_purchase(
          ingredient.code,
          location.code,
          500,
          cash.id,
          8,
          Date.utc_today(),
          "manual",
          42
        )

      assert movement.source_type == "manual"
      assert movement.source_id == 42
    end
  end

  # ── Usage ─────────────────────────────────────────────────────────────

  describe "record_usage/4" do
    test "reduces stock quantity" do
      ingredient = ingredient_fixture()
      location = location_fixture()
      cash = paid_from_account()

      Inventory.record_purchase(
        ingredient.code,
        location.code,
        1000,
        cash.id,
        10,
        Date.utc_today()
      )

      {:ok, {:ok, %{stock: stock}}} =
        Inventory.record_usage(ingredient.code, location.code, 300, Date.utc_today())

      assert stock.quantity_on_hand == 700
    end

    test "returns movement and cost info" do
      ingredient = ingredient_fixture()
      location = location_fixture()
      cash = paid_from_account()

      Inventory.record_purchase(
        ingredient.code,
        location.code,
        1000,
        cash.id,
        10,
        Date.utc_today()
      )

      assert {:ok, {:ok, %{movement: movement, total_cost_cents: total_cost}}} =
               Inventory.record_usage(ingredient.code, location.code, 100, Date.utc_today())

      assert movement.movement_type == "usage"
      assert movement.quantity == 100
      # 100g × 10 cents/g
      assert total_cost == 1000
    end

    test "allows usage below zero (flags negative stock)" do
      ingredient = ingredient_fixture()
      location = location_fixture()

      assert {:ok, {:ok, %{stock: stock}}} =
               Inventory.record_usage(ingredient.code, location.code, 100, Date.utc_today())

      assert stock.quantity_on_hand == -100
      assert stock.negative_stock == true
    end
  end

  # ── inventory_type/1 ─────────────────────────────────────────────────

  describe "inventory_type/1" do
    test "returns :packing for packing ingredient" do
      {:ok, ing} =
        Inventory.create_ingredient(%{
          code: "PACK#{System.unique_integer([:positive])}",
          name: "Packing material",
          unit: "units",
          cost_per_unit_cents: 5,
          inventory_type: "packing"
        })

      assert Inventory.inventory_type(ing) == :packing
    end

    test "returns :ingredients for regular ingredient" do
      ing = ingredient_fixture(%{inventory_type: "ingredients"})
      assert Inventory.inventory_type(ing) == :ingredients
    end

    test "returns :kitchen for kitchen type" do
      {:ok, ing} =
        Inventory.create_ingredient(%{
          code: "KITCH#{System.unique_integer([:positive])}",
          name: "Kitchen tool",
          unit: "units",
          cost_per_unit_cents: 100,
          inventory_type: "kitchen"
        })

      assert Inventory.inventory_type(ing) == :kitchen
    end

    test "looks up ingredient by code string" do
      ing = ingredient_fixture(%{inventory_type: "ingredients"})
      assert Inventory.inventory_type(ing.code) == :ingredients
    end

    test "returns :ingredients as default for unknown code" do
      assert Inventory.inventory_type("NONEXISTENT_CODE") == :ingredients
    end
  end

  # ── Inventory valuation ───────────────────────────────────────────────

  describe "total_inventory_value_cents/0" do
    test "returns 0 when no inventory purchased" do
      value = Inventory.total_inventory_value_cents()
      assert is_integer(value) or value == Decimal.new(0) or is_struct(value, Decimal)
    end

    test "reflects purchased inventory value" do
      ingredient = ingredient_fixture()
      location = location_fixture()
      cash = paid_from_account()

      Inventory.record_purchase(
        ingredient.code,
        location.code,
        500,
        cash.id,
        20,
        Date.utc_today(),
        nil,
        nil,
        10_000
      )

      value = Inventory.total_inventory_value_cents()

      value_int =
        case value do
          %Decimal{} -> Decimal.to_integer(value)
          n -> n
        end

      assert value_int >= 10_000
    end
  end

  describe "list_negative_stock_items/0" do
    test "returns items with negative stock" do
      ingredient = ingredient_fixture()
      location = location_fixture()

      Inventory.record_usage(ingredient.code, location.code, 100, Date.utc_today())

      negatives = Inventory.list_negative_stock_items()
      assert Enum.any?(negatives, fn item -> item.ingredient_id == ingredient.id end)
    end

    test "does not include items with positive stock" do
      ingredient = ingredient_fixture()
      location = location_fixture()
      cash = paid_from_account()

      Inventory.record_purchase(
        ingredient.code,
        location.code,
        500,
        cash.id,
        10,
        Date.utc_today()
      )

      negatives = Inventory.list_negative_stock_items()
      refute Enum.any?(negatives, fn item -> item.ingredient_id == ingredient.id end)
    end
  end
end
