defmodule Ledgr.Repo.Migrations.CreateIngredientsInventoriesAndMovements do
  use Ecto.Migration

  def change do
    # ---------- Ingredients ----------
    create table(:ingredients) do
      # e.g. "FLOUR", "SUGAR", "BUTTER"
      add :code, :string, null: false
      # full name: "Wheat Flour"
      add :name, :string, null: false
      # "g", "ml", "unit", etc.
      add :unit, :string, null: false, default: "g"
      add :cost_per_unit_cents, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:ingredients, [:code])

    # ---------- Inventory Locations ----------
    create table(:inventory_locations) do
      # "MAIN_KITCHEN", "FREEZER", "WAREHOUSE"
      add :code, :string, null: false
      add :name, :string, null: false
      add :description, :text

      timestamps()
    end

    create unique_index(:inventory_locations, [:code])

    # ---------- Inventories ----------
    create table(:inventories) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :location_id, references(:inventory_locations, on_delete: :delete_all), null: false

      add :quantity_on_hand, :integer, null: false, default: 0
      add :avg_cost_per_unit_cents, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:inventories, [:ingredient_id, :location_id])

    # ---------- Inventory Movements ----------
    create table(:inventory_movements) do
      add :ingredient_id, references(:ingredients, on_delete: :restrict), null: false

      add :from_location_id, references(:inventory_locations)
      add :to_location_id, references(:inventory_locations)

      # always positive
      add :quantity, :integer, null: false
      # "purchase", "usage", "transfer", "adjustment"
      add :movement_type, :string, null: false

      add :unit_cost_cents, :integer, null: false, default: 0
      add :total_cost_cents, :integer, null: false, default: 0

      # "order", "expense", "manual"
      add :source_type, :string
      add :source_id, :integer
      add :note, :text

      timestamps(updated_at: false)
    end

    create index(:inventory_movements, [:ingredient_id])
    create index(:inventory_movements, [:from_location_id])
    create index(:inventory_movements, [:to_location_id])
    create index(:inventory_movements, [:source_type, :source_id])
  end
end
