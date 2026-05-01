defmodule Ledgr.Domains.MrMunchMe.InventoryLegacyTest do
  use Ledgr.DataCase, async: true

  import Ecto.Query

  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Repo
  alias Ledgr.Domains.MrMunchMe.Inventory.{Ingredient, Location, InventoryItem, InventoryMovement}
  alias Ledgr.Core.Accounting.JournalEntry

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

    # Create ingredient
    {:ok, ingredient} =
      %Ingredient{}
      |> Ingredient.changeset(%{
        code: "FLOUR",
        name: "Flour",
        unit: "g"
      })
      |> Repo.insert()

    # Create locations
    {:ok, location} =
      %Location{}
      |> Location.changeset(%{
        code: "WAREHOUSE",
        name: "Warehouse"
      })
      |> Repo.insert()

    {:ok, from_location} =
      %Location{}
      |> Location.changeset(%{
        code: "KITCHEN",
        name: "Kitchen"
      })
      |> Repo.insert()

    {
      :ok,
      cash_account: cash_account,
      ingredients_account: ingredients_account,
      ingredient: ingredient,
      location: location,
      from_location: from_location
    }
  end

  describe "delete_purchase/1" do
    test "successfully deletes a purchase and reverses inventory changes", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create a purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      assert {:ok, _} = Inventory.create_purchase(purchase_attrs)

      # Verify stock was created
      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.quantity_on_hand == 1000
      # 50.00 pesos = 5000 cents, 5000 / 1000 = 5 cents per unit
      assert stock.avg_cost_per_unit_cents == 5

      # Get the movement
      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "purchase" and m.ingredient_id == ^ingredient.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      # Verify journal entry was created
      journal_entry =
        Repo.one(
          from je in JournalEntry,
            where: je.entry_type == "inventory_purchase",
            order_by: [desc: je.inserted_at],
            limit: 1
        )

      assert journal_entry != nil

      # Delete the purchase
      assert {:ok, _} = Inventory.delete_purchase(movement.id)

      # Verify movement is deleted
      refute Repo.get(InventoryMovement, movement.id)

      # Verify inventory was reversed
      stock = Repo.get(InventoryItem, stock.id)
      assert stock.quantity_on_hand == 0
      assert stock.avg_cost_per_unit_cents == 0

      # Verify journal entry was deleted
      refute Repo.get(JournalEntry, journal_entry.id)
    end

    test "reverses inventory correctly when there was existing stock", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create first purchase
      purchase1_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      assert {:ok, _} = Inventory.create_purchase(purchase1_attrs)

      # Create second purchase
      purchase2_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 500,
        "total_cost_pesos" => "30.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      assert {:ok, _} = Inventory.create_purchase(purchase2_attrs)

      # Verify stock after both purchases
      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.quantity_on_hand == 1500
      # Average cost: (1000 * 5 + 500 * 6) / 1500 = 5333 / 1500 = 3.55... cents
      # First purchase: 50.00 pesos = 5000 cents / 1000 = 5 cents per unit
      # Second purchase: 30.00 pesos = 3000 cents / 500 = 6 cents per unit
      # Weighted average: (1000 * 5 + 500 * 6) / 1500 = 8000 / 1500 = 5.33... cents
      expected_avg = div(1000 * 5 + 500 * 6, 1500)
      assert stock.avg_cost_per_unit_cents == expected_avg

      # Get the second movement by filtering for the one with 500 quantity
      # (30.00 pesos = 3000 cents total)
      second_movement =
        Repo.one!(
          from m in InventoryMovement,
            where:
              m.movement_type == "purchase" and m.ingredient_id == ^ingredient.id and
                m.quantity == 500
        )

      # Verify it's the correct one (500 units, 30.00 pesos = 3000 cents)
      assert second_movement.quantity == 500
      assert second_movement.total_cost_cents == 3000

      # Delete the second purchase
      assert {:ok, _} = Inventory.delete_purchase(second_movement.id)

      # Verify inventory was reversed to first purchase state
      stock = Repo.get(InventoryItem, stock.id)
      assert stock.quantity_on_hand == 1000
      # Should approximate the original cost (5 cents per unit)
      # The delete function uses an approximation, so we allow some variance
      # Allow small rounding differences
      assert stock.avg_cost_per_unit_cents in [5, 4, 6]
    end

    test "returns error when trying to delete a non-purchase movement", %{
      cash_account: cash_account,
      ingredient: ingredient,
      from_location: from_location,
      location: location
    } do
      # First create stock in from_location
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => from_location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      assert {:ok, _} = Inventory.create_purchase(purchase_attrs)

      # Create a transfer
      {:ok, _} =
        Inventory.create_movement(%{
          "movement_type" => "transfer",
          "ingredient_code" => ingredient.code,
          "from_location_code" => from_location.code,
          "to_location_code" => location.code,
          "quantity" => 500,
          "movement_date" => Date.utc_today()
        })

      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "transfer" and m.ingredient_id == ^ingredient.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      # Try to delete it as a purchase
      assert {:error, :not_a_purchase} = Inventory.delete_purchase(movement.id)

      # Verify movement still exists
      assert Repo.get(InventoryMovement, movement.id)
    end
  end

  describe "delete_transfer/1" do
    test "successfully deletes a transfer and reverses inventory changes", %{
      cash_account: cash_account,
      ingredient: ingredient,
      from_location: from_location,
      location: location
    } do
      # First create stock in from_location
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => from_location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      assert {:ok, _} = Inventory.create_purchase(purchase_attrs)

      # Create a transfer
      {:ok, _} =
        Inventory.create_movement(%{
          "movement_type" => "transfer",
          "ingredient_code" => ingredient.code,
          "from_location_code" => from_location.code,
          "to_location_code" => location.code,
          "quantity" => 500,
          "movement_date" => Date.utc_today()
        })

      # Verify stock after transfer
      from_stock = Inventory.get_or_create_stock!(ingredient.id, from_location.id)
      to_stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert from_stock.quantity_on_hand == 500
      assert to_stock.quantity_on_hand == 500

      # Get the transfer movement
      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "transfer" and m.ingredient_id == ^ingredient.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      # Delete the transfer
      assert {:ok, _} = Inventory.delete_transfer(movement.id)

      # Verify movement is deleted
      refute Repo.get(InventoryMovement, movement.id)

      # Verify inventory was reversed
      from_stock = Repo.get(InventoryItem, from_stock.id)
      to_stock = Repo.get(InventoryItem, to_stock.id)
      assert from_stock.quantity_on_hand == 1000
      assert to_stock.quantity_on_hand == 0
    end

    test "returns error when trying to delete a non-transfer movement", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create a purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      assert {:ok, _} = Inventory.create_purchase(purchase_attrs)

      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "purchase" and m.ingredient_id == ^ingredient.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      # Try to delete it as a transfer
      assert {:error, :not_a_transfer} = Inventory.delete_transfer(movement.id)

      # Verify movement still exists
      assert Repo.get(InventoryMovement, movement.id)
    end
  end

  describe "ingredients CRUD" do
    test "list_ingredients/0 returns all ingredients ordered by name" do
      {:ok, _apple} = Inventory.create_ingredient(%{code: "APPLE", name: "Apple", unit: "g"})
      {:ok, _banana} = Inventory.create_ingredient(%{code: "BANANA", name: "Banana", unit: "g"})

      ingredients = Inventory.list_ingredients()
      names = Enum.map(ingredients, & &1.name)

      # Should be sorted alphabetically
      assert "Apple" in names
      assert "Banana" in names
      apple_idx = Enum.find_index(names, &(&1 == "Apple"))
      banana_idx = Enum.find_index(names, &(&1 == "Banana"))
      assert apple_idx < banana_idx
    end

    test "get_ingredient!/1 returns ingredient by id", %{ingredient: ingredient} do
      result = Inventory.get_ingredient!(ingredient.id)
      assert result.id == ingredient.id
      assert result.code == ingredient.code
    end

    test "create_ingredient/1 creates with valid attrs" do
      attrs = %{code: "SUGAR", name: "Sugar", unit: "g", cost_per_unit_cents: 2}
      assert {:ok, %Ingredient{} = ingredient} = Inventory.create_ingredient(attrs)
      assert ingredient.code == "SUGAR"
      assert ingredient.name == "Sugar"
    end

    test "update_ingredient/2 updates the ingredient", %{ingredient: ingredient} do
      assert {:ok, updated} =
               Inventory.update_ingredient(ingredient, %{name: "Whole Wheat Flour"})

      assert updated.name == "Whole Wheat Flour"
    end

    test "delete_ingredient/1 deletes the ingredient" do
      {:ok, ingredient} = Inventory.create_ingredient(%{code: "TEMP", name: "Temp", unit: "g"})
      assert {:ok, _} = Inventory.delete_ingredient(ingredient)
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_ingredient!(ingredient.id) end
    end

    test "change_ingredient/2 returns a changeset", %{ingredient: ingredient} do
      changeset = Inventory.change_ingredient(ingredient, %{name: "New Name"})
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "locations" do
    test "list_locations/0 returns all locations", %{
      location: location,
      from_location: from_location
    } do
      locations = Inventory.list_locations()
      codes = Enum.map(locations, & &1.code)

      assert location.code in codes
      assert from_location.code in codes
    end

    test "location_select_options/0 returns formatted options", %{location: location} do
      options = Inventory.location_select_options()
      assert is_list(options)
      # Options are {name, code} tuples
      assert Enum.any?(options, fn {_name, code} -> code == location.code end)
    end
  end

  describe "stock management" do
    test "get_or_create_stock!/2 creates stock if not exists", %{
      ingredient: ingredient,
      location: location
    } do
      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.quantity_on_hand == 0
      assert stock.avg_cost_per_unit_cents == 0
    end

    test "get_or_create_stock!/2 returns existing stock", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create initial stock via purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 500,
        "total_cost_pesos" => "25.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      # Get stock - should return existing
      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.quantity_on_hand == 500
    end

    test "list_stock_items/0 returns stock with preloaded associations", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create stock
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 100,
        "total_cost_pesos" => "10.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      items = Inventory.list_stock_items()
      assert length(items) >= 1

      # Check preloads are available
      item = Enum.find(items, fn i -> i.ingredient_id == ingredient.id end)
      assert item.ingredient != nil
      assert item.location != nil
    end
  end

  describe "inventory_type/1" do
    test "returns :packing for packing ingredients" do
      # Create a packing ingredient
      {:ok, packing} =
        Inventory.create_ingredient(%{
          code: "PAQ_BOX",
          name: "Box",
          unit: "pcs",
          inventory_type: "packing"
        })

      assert Inventory.inventory_type(packing) == :packing
    end

    test "returns :kitchen for kitchen ingredients" do
      # Create a kitchen ingredient
      {:ok, kitchen} =
        Inventory.create_ingredient(%{
          code: "EQUIP_MIXER",
          name: "Mixer",
          unit: "pcs",
          inventory_type: "kitchen"
        })

      assert Inventory.inventory_type(kitchen) == :kitchen
    end

    test "returns :ingredients for regular ingredients" do
      {:ok, flour} = Inventory.create_ingredient(%{code: "FLOUR2", name: "Flour", unit: "g"})
      assert Inventory.inventory_type(flour) == :ingredients
    end

    test "defaults to :ingredients when no inventory_type set", %{ingredient: ingredient} do
      assert Inventory.inventory_type(ingredient) == :ingredients
    end
  end

  describe "movements" do
    test "list_recent_movements/1 returns movements", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create a purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 100,
        "total_cost_pesos" => "10.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      movements = Inventory.list_recent_movements(10)
      assert length(movements) >= 1

      # Verify preloads
      movement = hd(movements)
      assert movement.ingredient != nil
    end

    test "get_movement!/1 returns movement by id", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 100,
        "total_cost_pesos" => "10.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.ingredient_id == ^ingredient.id,
            limit: 1
        )

      result = Inventory.get_movement!(movement.id)
      assert result.id == movement.id
    end

    test "search_movements/1 filters by ingredient", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 100,
        "total_cost_pesos" => "10.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      movements = Inventory.search_movements(ingredient_id: ingredient.id)
      assert length(movements) >= 1
      assert Enum.all?(movements, fn m -> m.ingredient_id == ingredient.id end)
    end

    test "search_movements/1 filters by movement_type", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 100,
        "total_cost_pesos" => "10.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      movements = Inventory.search_movements(movement_type: "purchase")
      assert length(movements) >= 1
      assert Enum.all?(movements, fn m -> m.movement_type == "purchase" end)
    end
  end

  describe "total_inventory_value_cents/0" do
    test "calculates total inventory value", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create a purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      value = Inventory.total_inventory_value_cents()
      # 1000 units at 5 cents = 5000 cents
      assert value >= 5000
    end
  end

  describe "ingredient_quick_infos/0" do
    test "returns quick info for ingredients with purchases", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create a purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      infos = Inventory.ingredient_quick_infos()
      # Returns a map with {code => %{"unit" => ..., "avg_cost_cents" => ...}}
      info = Map.get(infos, ingredient.code)

      assert info != nil
      # 5000 cents / 1000 units = 5 cents
      assert info["avg_cost_cents"] == 5
    end
  end

  describe "return_purchase/3" do
    test "creates a return movement and reverses inventory", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create initial purchase
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      # Get the purchase movement
      purchase_movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "purchase" and m.ingredient_id == ^ingredient.id,
            limit: 1
        )

      # Return the purchase
      {:ok, _return_movement} = Inventory.return_purchase(purchase_movement.id)

      # Verify stock was reduced
      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.quantity_on_hand == 0
    end
  end

  describe "record_write_off/4" do
    test "creates write-off movement and reduces inventory", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create required waste expense account
      {:ok, _waste_account} =
        Accounting.create_account(%{
          code: "6060",
          name: "Inventory Waste",
          type: "expense",
          normal_balance: "debit",
          is_cash: false
        })

      # First create stock
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 1000,
        "total_cost_pesos" => "50.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      # Record write-off (uses positional args)
      {:ok, _movement} =
        Inventory.record_write_off(
          ingredient.code,
          location.code,
          200,
          Date.utc_today()
        )

      # Verify stock was reduced
      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.quantity_on_hand == 800
    end
  end

  describe "batch_inventory_values/0" do
    test "returns a map keyed by {ingredient_id, location_id} with cost_cents", %{
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      purchase_attrs = %{
        "ingredient_code" => ingredient.code,
        "location_code" => location.code,
        "quantity" => 100,
        "total_cost_pesos" => "10.00",
        "paid_from_account_id" => to_string(cash_account.id),
        "purchase_date" => Date.utc_today()
      }

      {:ok, _} = Inventory.create_purchase(purchase_attrs)

      result = Inventory.batch_inventory_values()

      assert is_map(result)
      key = {ingredient.id, location.id}
      assert Map.has_key?(result, key)
      assert result[key] == 1000
    end

    test "returns empty map when no movements exist" do
      result = Inventory.batch_inventory_values()
      assert result == %{}
    end
  end
end
