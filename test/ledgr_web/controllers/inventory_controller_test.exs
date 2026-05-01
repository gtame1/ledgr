defmodule LedgrWeb.Domains.MrMunchMe.InventoryControllerTest do
  use LedgrWeb.ConnCase

  import Ecto.Query

  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Repo
  alias Ledgr.Domains.MrMunchMe.Inventory.{Ingredient, Location, InventoryMovement}

  setup %{conn: conn} do
    conn = log_in_user(conn)

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

    {:ok, _ingredients_cogs_account} =
      Accounting.create_account(%{
        code: "5000",
        name: "Ingredients COGS",
        type: "expense",
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

    # Create location
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
      conn: conn,
      cash_account: cash_account,
      ingredients_account: ingredients_account,
      ingredient: ingredient,
      location: location,
      from_location: from_location
    }
  end

  describe "delete_purchase/2" do
    test "successfully deletes a purchase and redirects with hash fragment", %{
      conn: conn,
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

      # Get the created movement
      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "purchase" and m.ingredient_id == ^ingredient.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      assert movement != nil

      # Delete the purchase
      conn = delete(conn, "/app/mr-munch-me/inventory/purchases/#{movement.id}")

      assert redirected_to(conn) == "/app/mr-munch-me/inventory#recent_movements_card"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Purchase deleted successfully."

      # Verify movement is deleted
      refute Repo.get(InventoryMovement, movement.id)

      # Verify inventory was reversed
      stock = Inventory.get_or_create_stock!(ingredient.id, location.id)
      assert stock.quantity_on_hand == 0
      assert stock.avg_cost_per_unit_cents == 0
    end

    test "returns error when trying to delete a non-purchase movement", %{
      conn: conn,
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

      # Create a transfer movement (not a purchase)
      {:ok, _} =
        Inventory.create_movement(%{
          "movement_type" => "transfer",
          "ingredient_code" => ingredient.code,
          "from_location_code" => from_location.code,
          "to_location_code" => location.code,
          "quantity" => 500,
          "movement_date" => Date.utc_today()
        })

      # Get the created movement
      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "transfer" and m.ingredient_id == ^ingredient.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      # Try to delete it as a purchase
      conn = delete(conn, "/app/mr-munch-me/inventory/purchases/#{movement.id}")

      assert redirected_to(conn) == "/app/mr-munch-me/inventory"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "This movement is not a purchase."

      # Verify movement still exists
      assert Repo.get(InventoryMovement, movement.id)
    end
  end

  describe "delete_movement/2" do
    test "successfully deletes a transfer and redirects with hash fragment", %{
      conn: conn,
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

      # Get the created movement
      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "transfer" and m.ingredient_id == ^ingredient.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      assert movement != nil

      # Delete the transfer
      conn = delete(conn, "/app/mr-munch-me/inventory/movements/#{movement.id}")

      assert redirected_to(conn) == "/app/mr-munch-me/inventory#recent_movements_card"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Transfer deleted successfully."

      # Verify movement is deleted
      refute Repo.get(InventoryMovement, movement.id)
    end

    test "returns error when trying to delete a non-transfer movement", %{
      conn: conn,
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # Create a purchase (not a transfer)
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
      conn = delete(conn, "/app/mr-munch-me/inventory/movements/#{movement.id}")

      assert redirected_to(conn) == "/app/mr-munch-me/inventory"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Only transfers can be deleted."

      # Verify movement still exists
      assert Repo.get(InventoryMovement, movement.id)
    end

    test "returns error when trying to delete a usage movement", %{
      conn: conn,
      cash_account: cash_account,
      ingredient: ingredient,
      location: location
    } do
      # First create some stock
      {:ok, _} =
        Inventory.create_purchase(%{
          "ingredient_code" => ingredient.code,
          "location_code" => location.code,
          "quantity" => 1000,
          "total_cost_pesos" => "50.00",
          "paid_from_account_id" => to_string(cash_account.id),
          "purchase_date" => Date.utc_today()
        })

      # Create a usage movement
      {:ok, _} =
        Inventory.create_movement(%{
          "movement_type" => "usage",
          "ingredient_code" => ingredient.code,
          "from_location_code" => location.code,
          "quantity" => 200,
          "movement_date" => Date.utc_today()
        })

      movement =
        Repo.one(
          from m in InventoryMovement,
            where: m.movement_type == "usage" and m.ingredient_id == ^ingredient.id,
            order_by: [desc: m.inserted_at],
            limit: 1
        )

      # Try to delete it
      conn = delete(conn, "/app/mr-munch-me/inventory/movements/#{movement.id}")

      assert redirected_to(conn) == "/app/mr-munch-me/inventory"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Only transfers can be deleted."

      # Verify movement still exists
      assert Repo.get(InventoryMovement, movement.id)
    end
  end
end
