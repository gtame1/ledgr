defmodule Ledgr.Repo.Migrations.BackfillIngredientInventoryTypes do
  use Ecto.Migration

  def up do
    # Packing codes
    packing_codes = ["BOLSA_CELOFAN", "ESTAMPAS", "LISTONES", "BASE_GRANDE", "BASE_MEDIANA"]
    # Kitchen codes
    kitchen_codes = ["MOLDE_GRANDE", "MOLDE_MEDIANO", "MOLDE_MINI"]

    # Update packing ingredients
    for code <- packing_codes do
      execute("UPDATE ingredients SET inventory_type = 'packing' WHERE code = '#{code}'")
    end

    # Update kitchen ingredients
    for code <- kitchen_codes do
      execute("UPDATE ingredients SET inventory_type = 'kitchen' WHERE code = '#{code}'")
    end

    # Ensure all other ingredients are set to 'ingredients' (default should already be set, but just in case)
    execute(
      "UPDATE ingredients SET inventory_type = 'ingredients' WHERE inventory_type IS NULL OR inventory_type = ''"
    )
  end

  def down do
    # This migration is not reversible in a meaningful way
    # We'd lose the inventory_type data anyway
    execute("UPDATE ingredients SET inventory_type = 'ingredients'")
  end
end
