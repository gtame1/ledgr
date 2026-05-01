defmodule Ledgr.Domains.MrMunchMe.Inventory.Recepies do
  @moduledoc """
  Recepies context: recipes for products.
  """
  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Domains.MrMunchMe.Orders.ProductVariant
  alias Ledgr.Domains.MrMunchMe.Inventory.{Recipe}
  alias Ledgr.Domains.MrMunchMe.Inventory

  @packaging_codes ~w(
    PACKING_PLASTICO
    BOLSA_CELOFAN
    ESTAMPAS
    LISTONES
  )

  def packaging_code?(code) when is_binary(code), do: code in @packaging_codes

  @doc """
  Return the recipe for a given product variant as a list of ingredient maps.
  Prefers DB-stored recipe keyed by variant_id; falls back to hardcoded recipes
  using the variant's SKU (same codes as the original product SKUs).
  """
  def recipe_for_variant(%ProductVariant{} = variant, date \\ nil) do
    case get_active_recipe(variant, date) do
      nil ->
        fallback_recipe_for_sku(variant.sku)

      recipe ->
        recipe
        |> Repo.preload(:recipe_lines)
        |> Map.get(:recipe_lines, [])
        |> Enum.map(fn line ->
          %{
            ingredient_code: line.ingredient_code,
            quantity: Decimal.to_float(line.quantity)
          }
        end)
    end
  end

  @doc """
  Get the active recipe for a product variant on a given date.
  Returns the recipe with the most recent effective_date <= date.
  If date is nil, returns the most recent recipe.
  """
  def get_active_recipe(variant, date \\ nil)

  def get_active_recipe(%ProductVariant{} = variant, date) do
    query =
      from r in Recipe,
        where: r.variant_id == ^variant.id,
        order_by: [desc: r.effective_date],
        limit: 1

    query =
      if date do
        from r in query, where: r.effective_date <= ^date
      else
        query
      end

    Repo.one(query)
  end

  @doc """
  List the most recent recipe for each product, ordered by effective_date descending.
  Only shows the latest version of each recipe (hides deprecated/older versions).
  """
  def list_recipes do
    # Find the most recent effective_date for each variant
    latest_dates =
      from r in Recipe,
        group_by: r.variant_id,
        select: %{
          variant_id: r.variant_id,
          max_date: max(r.effective_date)
        }

    # Get recipes that match the latest date for each variant
    from(r in Recipe,
      inner_join: latest in subquery(latest_dates),
      on: r.variant_id == latest.variant_id and r.effective_date == latest.max_date,
      order_by: [desc: r.effective_date],
      preload: [:recipe_lines, variant: :product]
    )
    |> Repo.all()
  end

  @doc """
  List all recipes for a product variant, ordered by effective_date descending.
  """
  def list_recipes_for_variant(%ProductVariant{} = variant) do
    from(r in Recipe,
      where: r.variant_id == ^variant.id,
      order_by: [desc: r.effective_date],
      preload: [:recipe_lines, variant: :product]
    )
    |> Repo.all()
  end

  @doc """
  Get all recipe versions grouped by variant_id.
  Returns a map where keys are variant_ids and values are lists of recipes.
  """
  def list_all_recipe_versions_by_variant do
    from(r in Recipe,
      order_by: [r.variant_id, desc: r.effective_date],
      preload: [:recipe_lines, variant: :product]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.variant_id)
  end

  @doc """
  Get a recipe by ID with preloaded recipe lines and product.
  """
  def get_recipe!(id) do
    Recipe
    |> Repo.get!(id)
    |> Repo.preload([:recipe_lines, variant: :product])
  end

  @doc """
  Create a new recipe with its lines.
  """
  def create_recipe(attrs \\ %{}) do
    %Recipe{}
    |> Recipe.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a recipe and its lines.
  """
  def update_recipe(%Recipe{} = recipe, attrs) do
    recipe
    |> Recipe.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a recipe.
  """
  def delete_recipe(%Recipe{} = recipe) do
    Repo.delete(recipe)
  end

  @doc """
  Returns a changeset for a recipe.
  """
  def change_recipe(%Recipe{} = recipe, attrs \\ %{}) do
    Recipe.changeset(recipe, attrs)
  end

  @doc """
  Copy a recipe from one variant to another.
  Creates a new recipe for the target variant with the same recipe lines.
  """
  def copy_recipe_from_variant(
        %ProductVariant{} = source_variant,
        %ProductVariant{} = target_variant,
        effective_date \\ LedgrWeb.Helpers.DomainHelpers.today_mx()
      ) do
    case get_active_recipe(source_variant) do
      nil ->
        {:error, :no_recipe_found}

      source_recipe ->
        source_recipe = Repo.preload(source_recipe, :recipe_lines)

        recipe_attrs = %{
          variant_id: target_variant.id,
          effective_date: effective_date,
          name: source_recipe.name || "#{target_variant.name} Recipe",
          description: source_recipe.description || "Recipe copied from #{source_variant.name}",
          recipe_lines:
            Enum.map(source_recipe.recipe_lines || [], fn line ->
              %{
                ingredient_code: line.ingredient_code,
                quantity: Decimal.to_string(line.quantity)
              }
            end)
        }

        create_recipe(recipe_attrs)
    end
  end

  @doc """
  Get options for variants that have recipes, for use in dropdowns.
  Returns a list of {label, variant_id} tuples.
  """
  def variants_with_recipes_select_options do
    from(r in Recipe,
      distinct: r.variant_id,
      join: v in assoc(r, :variant),
      join: p in assoc(v, :product),
      order_by: [p.name, v.name],
      select: {v.id, p.name, v.name}
    )
    |> Repo.all()
    |> Enum.map(fn {variant_id, product_name, variant_name} ->
      {"#{product_name} · #{variant_name}", variant_id}
    end)
  end

  @doc """
  Calculates the estimated total cost of a recipe based on average unit prices of ingredients.
  Returns the total cost in cents.
  Returns {:ok, total_cents} if all ingredients have costs.
  Returns {:partial, total_cents, missing_ingredients} if some ingredients are missing costs.
  """
  def estimated_recipe_cost(%Recipe{} = recipe) do
    recipe = Repo.preload(recipe, :recipe_lines)
    ingredient_infos = Inventory.ingredient_quick_infos()

    {total_cents, missing} =
      recipe.recipe_lines
      |> Enum.reduce({0, []}, fn line, {acc_cents, missing_acc} ->
        ingredient_code = line.ingredient_code
        quantity_decimal = line.quantity

        case Map.get(ingredient_infos, ingredient_code) do
          nil ->
            # Ingredient not found in quick infos
            {acc_cents, [ingredient_code | missing_acc]}

          %{"avg_cost_cents" => nil} ->
            # Ingredient exists but no average cost available
            {acc_cents, [ingredient_code | missing_acc]}

          %{"avg_cost_cents" => avg_cost_cents} when is_integer(avg_cost_cents) ->
            # Calculate cost: avg_cost_cents (cents per unit) * quantity (in ingredient's unit)
            quantity_float = Decimal.to_float(quantity_decimal)
            line_cost_cents = trunc(avg_cost_cents * quantity_float)
            {acc_cents + line_cost_cents, missing_acc}

          _ ->
            {acc_cents, missing_acc}
        end
      end)

    if missing == [] do
      {:ok, total_cents}
    else
      {:partial, total_cents, missing}
    end
  end

  # Shared SKU-based fallback so both the product path and the variant path
  # resolve to the same hardcoded ingredient lists.
  defp fallback_recipe_for_sku(sku) when is_binary(sku) do
    main_ingredients =
      case sku do
        "TAKIS-GRANDE" ->
          [%{ingredient_code: "TAKIS_FUEGO", quantity: 1020}]

        "TAKIS-MEDIANA" ->
          [%{ingredient_code: "TAKIS_FUEGO", quantity: 517}]

        "RUNNERS-GRANDE" ->
          [%{ingredient_code: "RUNNERS", quantity: 840}]

        "RUNNERS-MEDIANA" ->
          [%{ingredient_code: "RUNNERS", quantity: 447}]

        "MIXTA-GRANDE" ->
          [
            %{ingredient_code: "TAKIS_FUEGO", quantity: 340},
            %{ingredient_code: "RUNNERS", quantity: 280},
            %{ingredient_code: "CHIPS_FUEGO", quantity: 160}
          ]

        "MIXTA-MEDIANA" ->
          [
            %{ingredient_code: "TAKIS_FUEGO", quantity: 225},
            %{ingredient_code: "RUNNERS", quantity: 124},
            %{ingredient_code: "CHIPS_FUEGO", quantity: 77}
          ]

        "SALSA-NEGRAS-GRANDE" ->
          [
            %{ingredient_code: "CRUJIENTES_INGLESA", quantity: 240},
            %{ingredient_code: "DORITOS_INCOGNITA", quantity: 223},
            %{ingredient_code: "CACAHUATES_INGLESA", quantity: 160}
          ]

        "SALSA-NEGRAS-MEDIANA" ->
          [
            %{ingredient_code: "CRUJIENTES_INGLESA", quantity: 160},
            %{ingredient_code: "DORITOS_INCOGNITA", quantity: 178},
            %{ingredient_code: "CACAHUATES_INGLESA", quantity: 160}
          ]

        _ ->
          []
      end

    extra_ingredients =
      cond do
        sku == "SALSA-NEGRAS-GRANDE" ->
          [
            %{ingredient_code: "MIEL_KARO", quantity: 180},
            # ml
            %{ingredient_code: "MAGGI", quantity: 5},
            %{ingredient_code: "TAJIN", quantity: 30},
            %{ingredient_code: "LIMON", quantity: 1},
            %{ingredient_code: "PULPARINDIO", quantity: 2}
          ]

        sku == "SALSA-NEGRAS-MEDIANA" ->
          [
            %{ingredient_code: "MIEL_KARO", quantity: 100},
            %{ingredient_code: "MAGGI", quantity: 5},
            %{ingredient_code: "TAJIN", quantity: 15},
            %{ingredient_code: "LIMON", quantity: 0.5},
            %{ingredient_code: "PULPARINDIO", quantity: 1}
          ]

        sku in ["TAKIS-GRANDE", "RUNNERS-GRANDE", "MIXTA-GRANDE"] ->
          [
            # ml
            %{ingredient_code: "MIEL_KARO", quantity: 180},
            # ml
            %{ingredient_code: "SIRILO", quantity: 120},
            # g
            %{ingredient_code: "MIGUELITO", quantity: 30},
            # g
            %{ingredient_code: "TAJIN", quantity: 30},
            # unit
            %{ingredient_code: "LIMON", quantity: 1},
            # unit
            %{ingredient_code: "PULPARINDIO", quantity: 2}
          ]

        sku in ["TAKIS-MEDIANA", "RUNNERS-MEDIANA", "MIXTA-MEDIANA"] ->
          [
            %{ingredient_code: "MIEL_KARO", quantity: 100},
            %{ingredient_code: "SIRILO", quantity: 30},
            %{ingredient_code: "MIGUELITO", quantity: 15},
            %{ingredient_code: "TAJIN", quantity: 15},
            %{ingredient_code: "LIMON", quantity: 0.5},
            %{ingredient_code: "PULPARINDIO", quantity: 1}
          ]

        true ->
          []
      end

    packing_ingredients =
      [
        # unit
        %{ingredient_code: "BOLSA_CELOFAN", quantity: 1},
        # unit
        %{ingredient_code: "ESTAMPAS", quantity: 1},
        # cm
        %{ingredient_code: "LISTONES", quantity: 15}
      ] ++
        cond do
          # unit
          String.contains?(sku, "GRANDE") -> [%{ingredient_code: "BASE_GRANDE", quantity: 1}]
          # unit
          String.contains?(sku, "MEDIANA") -> [%{ingredient_code: "BASE_MEDIANA", quantity: 1}]
          true -> []
        end

    main_ingredients ++ extra_ingredients ++ packing_ingredients
  end

  defp fallback_recipe_for_sku(_sku), do: []
end
