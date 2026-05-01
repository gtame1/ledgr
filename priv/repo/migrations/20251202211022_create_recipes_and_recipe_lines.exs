defmodule Ledgr.Repo.Migrations.CreateRecipesAndRecipeLines do
  use Ecto.Migration

  def change do
    create table(:recipes) do
      add :product_id, references(:products, on_delete: :restrict), null: false
      add :effective_date, :date, null: false
      add :name, :string
      add :description, :text

      timestamps()
    end

    create unique_index(:recipes, [:product_id, :effective_date],
             name: :recipes_product_id_effective_date_index
           )

    create index(:recipes, [:product_id])
    create index(:recipes, [:effective_date])

    create table(:recipe_lines) do
      add :recipe_id, references(:recipes, on_delete: :delete_all), null: false
      add :ingredient_code, :string, null: false
      add :quantity, :decimal, null: false

      timestamps()
    end

    create index(:recipe_lines, [:recipe_id])
    create index(:recipe_lines, [:ingredient_code])
  end
end
