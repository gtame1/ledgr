defmodule LedgrWeb.Domains.MrMunchMe.RecipeController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Inventory.Recepies
  alias Ledgr.Domains.MrMunchMe.Inventory.Recipe
  alias Ledgr.Domains.MrMunchMe.Orders

  def index(conn, _params) do
    recipes = Recepies.list_recipes()
    recipe_versions_by_variant = Recepies.list_all_recipe_versions_by_variant()

    # Calculate estimated costs for each recipe
    recipes_with_costs =
      Enum.map(recipes, fn recipe ->
        estimated_cost = Recepies.estimated_recipe_cost(recipe)
        Map.put(recipe, :estimated_cost, estimated_cost)
      end)

    # Calculate estimated costs for all recipe versions
    recipe_versions_by_variant_with_costs =
      recipe_versions_by_variant
      |> Enum.map(fn {variant_id, versions} ->
        versions_with_costs =
          Enum.map(versions, fn version ->
            estimated_cost = Recepies.estimated_recipe_cost(version)
            Map.put(version, :estimated_cost, estimated_cost)
          end)
        {variant_id, versions_with_costs}
      end)
      |> Map.new()

    # Group latest recipes by product for the index view
    recipes_by_product =
      recipes_with_costs
      |> Enum.group_by(fn r -> {r.variant.product_id, r.variant.product.name} end)
      |> Enum.sort_by(fn {{_id, name}, _recipes} -> name end)

    # Find active variants (with active parent products) that have no recipe yet
    variant_ids_with_recipes = MapSet.new(recipes_with_costs, & &1.variant_id)

    variants_missing_recipes =
      Orders.list_all_active_variants_with_products()
      |> Enum.reject(&MapSet.member?(variant_ids_with_recipes, &1.id))
      |> Enum.group_by(& &1.product.name)
      |> Enum.sort_by(fn {name, _} -> name end)

    render(conn, :index,
      recipes: recipes_with_costs,
      recipe_versions_by_variant: recipe_versions_by_variant_with_costs,
      recipes_by_product: recipes_by_product,
      variants_missing_recipes: variants_missing_recipes
    )
  end

  def new(conn, _params) do
    # Initialize with at least one empty recipe line, defaulting to today
    today_mx = NaiveDateTime.utc_now() |> NaiveDateTime.add(-6 * 3600, :second) |> NaiveDateTime.to_date()
    attrs = %{"effective_date" => Date.to_iso8601(today_mx), "recipe_lines" => [%{}]}
    changeset = Recepies.change_recipe(%Recipe{}, attrs)
    form = Phoenix.Component.to_form(changeset)

    ingredient_options_raw = Ledgr.Domains.MrMunchMe.Inventory.ingredient_options_with_units()
    ingredient_options = Enum.map(ingredient_options_raw, fn {name, code, _unit} -> {name, code} end)
    ingredient_options_json = Jason.encode!(Enum.map(ingredient_options_raw, fn {name, code, unit} -> [name, code, unit] end))

    render(conn, :new,
      changeset: changeset,
      form: form,
      action: dp(conn, "/recipes"),
      variant_options: Orders.variant_select_options(),
      ingredient_options: ingredient_options,
      ingredient_options_json: ingredient_options_json
    )
  end

  def create(conn, %{"recipe" => recipe_params}) do
    case Recepies.create_recipe(recipe_params) do
      {:ok, _recipe} ->
        conn
        |> put_flash(:info, "Recipe created successfully.")
        |> redirect(to: dp(conn, "/recipes"))

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :insert)
        form = Phoenix.Component.to_form(changeset)

        ingredient_options_raw = Ledgr.Domains.MrMunchMe.Inventory.ingredient_options_with_units()
        ingredient_options = Enum.map(ingredient_options_raw, fn {name, code, _unit} -> {name, code} end)
        ingredient_options_json = Jason.encode!(Enum.map(ingredient_options_raw, fn {name, code, unit} -> [name, code, unit] end))

        render(conn, :new,
          changeset: changeset,
          form: form,
          action: dp(conn, "/recipes"),
          variant_options: Orders.variant_select_options(),
          ingredient_options: ingredient_options,
          ingredient_options_json: ingredient_options_json
        )
    end
  end

  def show(conn, %{"id" => id}) do
    recipe = Recepies.get_recipe!(id)
    estimated_cost = Recepies.estimated_recipe_cost(recipe)
    render(conn, :show, recipe: recipe, estimated_cost: estimated_cost)
  end

  def edit(conn, %{"id" => id}) do
    original_recipe = Recepies.get_recipe!(id)

    # Pre-fill with existing recipe data but create a new recipe
    # Default effective_date to today (or day after original if original is today/future)
    today_mx = NaiveDateTime.utc_now() |> NaiveDateTime.add(-6 * 3600, :second) |> NaiveDateTime.to_date()

    new_effective_date =
      if original_recipe.effective_date >= today_mx do
        Date.add(original_recipe.effective_date, 1)
      else
        today_mx
      end

    # Build attrs from existing recipe for pre-filling
    attrs = %{
      "variant_id" => original_recipe.variant_id,
      "effective_date" => Date.to_iso8601(new_effective_date),
      "name" => original_recipe.name,
      "description" => original_recipe.description,
      "recipe_lines" =>
        Enum.map(original_recipe.recipe_lines || [], fn line ->
          %{
            "ingredient_code" => line.ingredient_code,
            "quantity" => Decimal.to_string(line.quantity),
            "comment" => line.comment
          }
        end)
    }

    # Ensure at least one empty recipe line if none exist
    attrs =
      if attrs["recipe_lines"] == [] do
        Map.put(attrs, "recipe_lines", [%{}])
      else
        attrs
      end

    changeset = Recepies.change_recipe(%Recipe{}, attrs)
    form = Phoenix.Component.to_form(changeset)

    ingredient_options_raw = Ledgr.Domains.MrMunchMe.Inventory.ingredient_options_with_units()
    ingredient_options = Enum.map(ingredient_options_raw, fn {name, code, _unit} -> {name, code} end)
    ingredient_options_json = Jason.encode!(Enum.map(ingredient_options_raw, fn {name, code, unit} -> [name, code, unit] end))

    render(conn, :edit,
      original_recipe: original_recipe,
      changeset: changeset,
      form: form,
      action: dp(conn, "/recipes/new_version/#{original_recipe.id}"),
      variant_options: Orders.variant_select_options(),
      ingredient_options: ingredient_options,
      ingredient_options_json: ingredient_options_json
    )
  end

  def create_new_version(conn, %{"id" => original_id, "recipe" => recipe_params}) do
    original_recipe = Recepies.get_recipe!(original_id)

    case Recepies.create_recipe(recipe_params) do
      {:ok, _new_recipe} ->
        conn
        |> put_flash(:info, "New recipe version created successfully. The original recipe remains unchanged for historical accuracy.")
        |> redirect(to: dp(conn, "/recipes"))

      {:error, %Ecto.Changeset{} = changeset} ->
        # Debug: Log errors for troubleshooting
        IO.inspect(changeset.errors, label: "Recipe errors")
        if changeset.changes[:recipe_lines] do
          Enum.each(changeset.changes.recipe_lines, fn line_changeset ->
            IO.inspect(line_changeset.errors, label: "Recipe line errors")
          end)
        end

        changeset = Map.put(changeset, :action, :insert)
        form = Phoenix.Component.to_form(changeset)

        ingredient_options_raw = Ledgr.Domains.MrMunchMe.Inventory.ingredient_options_with_units()
        ingredient_options = Enum.map(ingredient_options_raw, fn {name, code, _unit} -> {name, code} end)
        ingredient_options_json = Jason.encode!(Enum.map(ingredient_options_raw, fn {name, code, unit} -> [name, code, unit] end))

        conn
        |> put_flash(:error, "Please fix the errors below and try again.")
        |> render(:edit,
          original_recipe: original_recipe,
          changeset: changeset,
          form: form,
          action: dp(conn, "/recipes/new_version/#{original_recipe.id}"),
          variant_options: Orders.variant_select_options(),
          ingredient_options: ingredient_options,
          ingredient_options_json: ingredient_options_json
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    recipe = Recepies.get_recipe!(id)
    {:ok, _} = Recepies.delete_recipe(recipe)

    conn
    |> put_flash(:info, "Recipe deleted successfully.")
    |> redirect(to: dp(conn, "/recipes"))
  end
end

defmodule LedgrWeb.Domains.MrMunchMe.RecipeHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents
  import Phoenix.Naming

  embed_templates "recipe_html/*"
end
