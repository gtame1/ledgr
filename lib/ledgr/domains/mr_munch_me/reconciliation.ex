defmodule Ledgr.Domains.MrMunchMe.Reconciliation do
  @moduledoc """
  MrMunchMe-specific inventory reconciliation logic.

  Handles physical inventory count adjustments and the corresponding
  journal entries to keep the accounting in sync.
  """
  require Logger
  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Domains.MrMunchMe.Inventory.{Ingredient, Location, InventoryItem}

  @doc """
  Get the current quantity of an ingredient at a location.
  """
  def get_inventory_quantity(ingredient_id, location_id) do
    case Repo.get_by(InventoryItem, ingredient_id: ingredient_id, location_id: location_id) do
      nil -> 0
      item -> item.quantity_on_hand
    end
  end

  @doc """
  Get all ingredient×location combos with their quantities for reconciliation.
  Shows every ingredient at every location, even if quantity is 0 (no InventoryItem row).
  """
  def list_inventory_for_reconciliation do
    ingredients = Repo.all(from i in Ingredient, order_by: i.code)
    locations = Repo.all(from l in Location, order_by: l.code)

    # Build a lookup map: {ingredient_id, location_id} => InventoryItem
    stock_map =
      from(ii in InventoryItem, preload: [:ingredient, :location])
      |> Repo.all()
      |> Map.new(fn ii -> {{ii.ingredient_id, ii.location_id}, ii} end)

    for ingredient <- ingredients, location <- locations do
      case Map.get(stock_map, {ingredient.id, location.id}) do
        nil ->
          %{
            ingredient: ingredient,
            location: location,
            quantity_on_hand: 0,
            avg_cost_per_unit_cents: 0,
            total_value_cents: 0
          }

        item ->
          avg_cost = item.avg_cost_per_unit_cents || 0

          %{
            ingredient: ingredient,
            location: location,
            quantity_on_hand: item.quantity_on_hand,
            avg_cost_per_unit_cents: avg_cost,
            total_value_cents: item.quantity_on_hand * avg_cost
          }
      end
    end
  end

  @doc """
  Create an inventory reconciliation adjustment.
  Adjusts the inventory quantity to match the actual quantity.
  Creates a journal entry to adjust the inventory account balance.
  """
  def create_inventory_reconciliation(
        ingredient_id,
        location_id,
        actual_quantity,
        adjustment_date,
        description \\ nil
      ) do
    Logger.info(
      "create_inventory_reconciliation called with ingredient_id: #{ingredient_id}, location_id: #{location_id}, actual_quantity: #{actual_quantity}"
    )

    ingredient = Repo.get!(Ingredient, ingredient_id)
    location = Repo.get!(Location, location_id)

    Logger.info("Found ingredient: #{ingredient.code}, location: #{location.code}")

    system_quantity = get_inventory_quantity(ingredient_id, location_id)
    difference = actual_quantity - system_quantity

    Logger.info(
      "System quantity: #{system_quantity}, Actual quantity: #{actual_quantity}, Difference: #{difference}"
    )

    if difference == 0 do
      Logger.info("No adjustment needed - quantities match")
      {:error, "No adjustment needed - quantities match"}
    else
      Logger.info("Starting transaction for inventory reconciliation")

      Repo.transaction(fn ->
        # Update the inventory item
        item = Inventory.get_or_create_stock!(ingredient_id, location_id)
        avg_cost = item.avg_cost_per_unit_cents || ingredient.cost_per_unit_cents || 0

        # If avg_cost is 0, we can't calculate value difference, so use a default cost
        # This handles cases where inventory was never purchased but exists physically
        effective_avg_cost =
          if avg_cost == 0 do
            Logger.warning(
              "No average cost for #{ingredient.code}, using ingredient default cost or 1 cent"
            )

            ingredient.cost_per_unit_cents || 1
          else
            avg_cost
          end

        updated_item =
          item
          |> InventoryItem.changeset(%{quantity_on_hand: actual_quantity})
          |> Repo.update!()

        # Calculate the value difference (ensure it's an integer)
        raw_value = difference * effective_avg_cost

        value_difference_cents =
          case raw_value do
            val when is_float(val) -> round(val)
            val when is_integer(val) -> val
          end

        Logger.info(
          "Value difference calculated: difference=#{difference}, effective_avg_cost=#{effective_avg_cost}, raw_value=#{raw_value}, value_difference_cents=#{value_difference_cents}"
        )

        if value_difference_cents == 0 do
          Logger.error(
            "Value difference is 0, cannot create journal entry. difference=#{difference}, effective_avg_cost=#{effective_avg_cost}"
          )

          Repo.rollback("Cannot create adjustment with zero value difference")
        end

        # Determine inventory account based on ingredient type
        inv_type = Inventory.inventory_type(ingredient.code)

        inventory_account_code =
          case inv_type do
            # Ingredients Inventory
            :ingredients -> "1200"
            # Packing Materials Inventory
            :packing -> "1210"
            # Kitchen Equipment Inventory
            :kitchen -> "1300"
            _ -> "1200"
          end

        inventory_account = Accounting.get_account_by_code!(inventory_account_code)
        # Inventory Waste
        offset_account = Accounting.get_account_by_code!("6060")

        entry_description =
          if description && String.trim(description) != "" do
            description
          else
            "Inventory reconciliation adjustment: #{ingredient.code} @ #{location.code}"
          end

        entry_attrs = %{
          date: adjustment_date,
          entry_type: "reconciliation",
          reference: "Inventory Reconciliation: #{ingredient.code} @ #{location.code}",
          description: entry_description
        }

        # Ensure value_difference_cents is a positive integer
        abs_value_diff = abs(value_difference_cents) |> trunc()

        Logger.info("Preparing journal lines with abs_value_diff: #{abs_value_diff}")

        if abs_value_diff == 0 do
          Logger.error("abs_value_diff is 0, cannot create journal entry")
          Repo.rollback("Cannot create adjustment with zero value difference")
        end

        lines =
          if difference > 0 do
            # Actual is more than system - increase inventory
            line1 = %{
              account_id: inventory_account.id,
              debit_cents: abs_value_diff,
              credit_cents: 0,
              description:
                "Inventory increase: #{difference} #{ingredient.code} @ #{location.code}"
            }

            line2 = %{
              account_id: offset_account.id,
              debit_cents: 0,
              credit_cents: abs_value_diff,
              description: "Reconciliation adjustment offset"
            }

            Logger.info("Line 1: #{inspect(line1)}")
            Logger.info("Line 2: #{inspect(line2)}")
            [line1, line2]
          else
            # Actual is less than system - decrease inventory
            line1 = %{
              account_id: inventory_account.id,
              debit_cents: 0,
              credit_cents: abs_value_diff,
              description:
                "Inventory decrease: #{abs(difference)} #{ingredient.code} @ #{location.code}"
            }

            line2 = %{
              account_id: offset_account.id,
              debit_cents: abs_value_diff,
              credit_cents: 0,
              description: "Reconciliation adjustment offset"
            }

            Logger.info("Line 1: #{inspect(line1)}")
            Logger.info("Line 2: #{inspect(line2)}")
            [line1, line2]
          end

        Logger.info("Journal lines prepared: #{inspect(lines)}")

        Logger.info("Creating journal entry with attrs: #{inspect(entry_attrs)}")
        Logger.info("Journal lines: #{inspect(lines)}")

        case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
          {:ok, journal_entry} ->
            Logger.info("Journal entry created successfully: #{journal_entry.id}")
            {:ok, %{item: updated_item, journal_entry: journal_entry}}

          {:error, changeset} ->
            Logger.error("Failed to create journal entry: #{inspect(changeset.errors)}")
            Repo.rollback(changeset)
        end
      end)
      |> case do
        {:ok, result} ->
          Logger.info("Transaction completed successfully")
          {:ok, result}

        {:error, reason} ->
          Logger.error("Transaction failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
