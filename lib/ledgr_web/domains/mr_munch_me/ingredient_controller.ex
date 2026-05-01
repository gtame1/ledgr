defmodule LedgrWeb.Domains.MrMunchMe.IngredientController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Domains.MrMunchMe.Inventory.Ingredient

  def index(conn, _params) do
    ingredients = Inventory.list_ingredients()
    render(conn, :index, ingredients: ingredients)
  end

  def new(conn, _params) do
    changeset = Inventory.change_ingredient(%Ingredient{})

    inventory_type_options = [
      {"Ingredients", "ingredients"},
      {"Packing", "packing"},
      {"Kitchen Equipment", "kitchen"},
      {"Other", "other"}
    ]

    render(conn, :new,
      changeset: changeset,
      action: dp(conn, "/ingredients"),
      inventory_type_options: inventory_type_options
    )
  end

  defp convert_cost_pesos_to_cents(params) do
    case params["cost_per_unit_pesos"] do
      nil ->
        params

      "" ->
        Map.put(params, "cost_per_unit_cents", 0)

      pesos_str ->
        cents =
          pesos_str
          |> Decimal.new()
          |> Decimal.mult(100)
          |> Decimal.round(0)
          |> Decimal.to_integer()

        Map.put(params, "cost_per_unit_cents", cents)
    end
  end

  defp cost_cents_to_pesos(ingredient) do
    cents = ingredient.cost_per_unit_cents || 0
    Decimal.div(Decimal.new(cents), 100) |> Decimal.to_string(:normal)
  end

  def create(conn, %{"ingredient" => ingredient_params}) do
    ingredient_params = convert_cost_pesos_to_cents(ingredient_params)

    case Inventory.create_ingredient(ingredient_params) do
      {:ok, _ingredient} ->
        conn
        |> put_flash(:info, "Ingredient created successfully.")
        |> redirect(to: dp(conn, "/ingredients"))

      {:error, %Ecto.Changeset{} = changeset} ->
        # Preserve the pesos value the user entered
        pesos_val = ingredient_params["cost_per_unit_pesos"] || ""

        changeset =
          changeset
          |> Map.put(:action, :insert)
          |> Ecto.Changeset.put_change(:cost_per_unit_pesos, pesos_val)

        inventory_type_options = [
          {"Ingredients", "ingredients"},
          {"Packing", "packing"},
          {"Kitchen Equipment", "kitchen"}
        ]

        render(conn, :new,
          changeset: changeset,
          action: dp(conn, "/ingredients"),
          inventory_type_options: inventory_type_options
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    ingredient = Inventory.get_ingredient!(id)
    # Convert cents to pesos for the form display
    pesos_value = cost_cents_to_pesos(ingredient)

    changeset =
      ingredient
      |> Inventory.change_ingredient()
      |> Ecto.Changeset.put_change(:cost_per_unit_pesos, pesos_value)

    inventory_type_options = [
      {"Ingredients", "ingredients"},
      {"Packing", "packing"},
      {"Kitchen Equipment", "kitchen"},
      {"Other", "other"}
    ]

    render(conn, :edit,
      ingredient: ingredient,
      changeset: changeset,
      action: dp(conn, "/ingredients/#{ingredient.id}"),
      inventory_type_options: inventory_type_options
    )
  end

  def update(conn, %{"id" => id, "ingredient" => ingredient_params}) do
    ingredient = Inventory.get_ingredient!(id)
    ingredient_params = convert_cost_pesos_to_cents(ingredient_params)

    case Inventory.update_ingredient(ingredient, ingredient_params) do
      {:ok, _ingredient} ->
        conn
        |> put_flash(:info, "Ingredient updated successfully.")
        |> redirect(to: dp(conn, "/ingredients"))

      {:error, %Ecto.Changeset{} = changeset} ->
        # Preserve the pesos value the user entered
        pesos_val = ingredient_params["cost_per_unit_pesos"] || cost_cents_to_pesos(ingredient)

        changeset =
          changeset
          |> Map.put(:action, :update)
          |> Ecto.Changeset.put_change(:cost_per_unit_pesos, pesos_val)

        inventory_type_options = [
          {"Ingredients", "ingredients"},
          {"Packing", "packing"},
          {"Kitchen Equipment", "kitchen"}
        ]

        render(conn, :edit,
          ingredient: ingredient,
          changeset: changeset,
          action: dp(conn, "/ingredients/#{ingredient.id}"),
          inventory_type_options: inventory_type_options
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    ingredient = Inventory.get_ingredient!(id)
    {:ok, _} = Inventory.delete_ingredient(ingredient)

    conn
    |> put_flash(:info, "Ingredient deleted successfully.")
    |> redirect(to: dp(conn, "/ingredients"))
  end
end

defmodule LedgrWeb.Domains.MrMunchMe.IngredientHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents
  import Phoenix.Naming

  embed_templates "ingredient_html/*"
end
