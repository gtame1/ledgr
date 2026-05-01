defmodule LedgrWeb.Domains.MrMunchMe.VariantController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Orders
  alias Ledgr.Domains.MrMunchMe.Orders.ProductVariant
  alias Ledgr.Domains.MrMunchMe.Inventory.Recepies
  alias Ledgr.Domains.MrMunchMe.Inventory.Recipe
  alias Ledgr.Domains.MrMunchMe.Inventory

  def new(conn, %{"product_id" => product_id}) do
    product = Orders.get_product!(product_id)
    changeset = ProductVariant.changeset(%ProductVariant{}, %{})

    render(conn, :new,
      product: product,
      changeset: changeset,
      action: dp(conn, "/products/#{product_id}/variants")
    )
  end

  def create(conn, %{"product_id" => product_id, "variant" => variant_params}) do
    product = Orders.get_product!(product_id)
    variant_params = parse_price(variant_params) |> Map.put("product_id", product_id)

    case Orders.create_variant(variant_params) do
      {:ok, variant} ->
        conn
        |> put_flash(:info, "Variant created. Add a recipe below.")
        |> redirect(to: dp(conn, "/products/#{product_id}/variants/#{variant.id}/edit"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new,
          product: product,
          changeset: changeset,
          action: dp(conn, "/products/#{product_id}/variants")
        )
    end
  end

  def edit(conn, %{"product_id" => product_id, "id" => id} = params) do
    today_mx =
      NaiveDateTime.utc_now() |> NaiveDateTime.add(-6 * 3600, :second) |> NaiveDateTime.to_date()

    variant = Orders.get_variant!(id)
    changeset = ProductVariant.changeset(variant, %{})

    # Load current recipe (with lines preloaded)
    current_recipe =
      case Recepies.get_active_recipe(variant) do
        nil -> nil
        recipe -> Recepies.get_recipe!(recipe.id)
      end

    # Determine recipe form attrs based on mode:
    # 1) copy_recipe_from param → pre-fill from sibling variant's recipe
    # 2) existing recipe → pre-fill with current lines + bumped effective date
    # 3) no recipe yet → empty form with one blank line
    {recipe_attrs, copied_from_variant} =
      cond do
        params["copy_recipe_from"] not in [nil, ""] ->
          source_variant = Orders.get_variant!(params["copy_recipe_from"])

          case Recepies.get_active_recipe(source_variant) do
            nil ->
              {%{"effective_date" => Date.to_iso8601(today_mx), "recipe_lines" => [%{}]}, nil}

            source_recipe ->
              source_recipe = Recepies.get_recipe!(source_recipe.id)

              attrs = %{
                "variant_id" => id,
                "effective_date" => Date.to_iso8601(today_mx),
                "recipe_lines" =>
                  Enum.map(source_recipe.recipe_lines || [], fn line ->
                    %{
                      "ingredient_code" => line.ingredient_code,
                      "quantity" => Decimal.to_string(line.quantity),
                      "comment" => line.comment
                    }
                  end)
              }

              {attrs, source_recipe.variant}
          end

        current_recipe != nil ->
          new_effective_date =
            if Date.compare(current_recipe.effective_date, today_mx) != :lt do
              Date.add(current_recipe.effective_date, 1)
            else
              today_mx
            end

          attrs = %{
            "variant_id" => id,
            "effective_date" => Date.to_iso8601(new_effective_date),
            "name" => current_recipe.name,
            "description" => current_recipe.description,
            "recipe_lines" =>
              Enum.map(current_recipe.recipe_lines || [], fn line ->
                %{
                  "ingredient_code" => line.ingredient_code,
                  "quantity" => Decimal.to_string(line.quantity),
                  "comment" => line.comment
                }
              end)
          }

          {attrs, nil}

        true ->
          {%{"effective_date" => Date.to_iso8601(today_mx), "recipe_lines" => [%{}]}, nil}
      end

    recipe_changeset = Recepies.change_recipe(%Recipe{}, recipe_attrs)
    recipe_form = Phoenix.Component.to_form(recipe_changeset)

    # Variants that have recipes, excluding the current variant
    recipe_variant_options =
      Recepies.variants_with_recipes_select_options()
      |> Enum.reject(fn {_label, vid} -> vid == variant.id end)

    ingredient_options_raw = Inventory.ingredient_options_with_units()

    ingredient_options =
      Enum.map(ingredient_options_raw, fn {name, code, _unit} -> {name, code} end)

    ingredient_options_json =
      Jason.encode!(
        Enum.map(ingredient_options_raw, fn {name, code, unit} -> [name, code, unit] end)
      )

    render(conn, :edit,
      variant: variant,
      product: variant.product,
      changeset: changeset,
      action: dp(conn, "/products/#{product_id}/variants/#{id}"),
      current_recipe: current_recipe,
      recipe_form: recipe_form,
      recipe_action: dp(conn, "/products/#{product_id}/variants/#{id}/recipe"),
      recipe_variant_options: recipe_variant_options,
      ingredient_options: ingredient_options,
      ingredient_options_json: ingredient_options_json,
      copied_from_variant: copied_from_variant
    )
  end

  def update(conn, %{"product_id" => product_id, "id" => id, "variant" => variant_params}) do
    variant = Orders.get_variant!(id)
    variant_params = parse_price(variant_params)

    case Orders.update_variant(variant, variant_params) do
      {:ok, _variant} ->
        conn
        |> put_flash(:info, "Variant updated successfully.")
        |> redirect(to: dp(conn, "/products/#{product_id}/edit"))

      {:error, %Ecto.Changeset{} = changeset} ->
        recipe_assigns = build_default_recipe_assigns(conn, variant, product_id)

        render(
          conn,
          :edit,
          [
            variant: variant,
            product: variant.product,
            changeset: Map.put(changeset, :action, :update),
            action: dp(conn, "/products/#{product_id}/variants/#{id}")
          ] ++ recipe_assigns
        )
    end
  end

  def delete(conn, %{"product_id" => product_id, "id" => id}) do
    variant = Orders.get_variant!(id)
    {:ok, _} = Orders.delete_variant(variant)

    conn
    |> put_flash(:info, "Variant deleted.")
    |> redirect(to: dp(conn, "/products/#{product_id}/edit"))
  end

  def save_recipe(conn, %{
        "product_id" => product_id,
        "variant_id" => variant_id,
        "recipe" => recipe_params
      }) do
    variant = Orders.get_variant!(variant_id)

    # Lock variant_id from URL — ignore whatever the form submitted
    recipe_params = Map.put(recipe_params, "variant_id", variant_id)

    case Recepies.create_recipe(recipe_params) do
      {:ok, _recipe} ->
        conn
        |> put_flash(:info, "Recipe saved.")
        |> redirect(to: dp(conn, "/products/#{product_id}/variants/#{variant_id}/edit"))

      {:error, %Ecto.Changeset{} = recipe_changeset} ->
        recipe_changeset = Map.put(recipe_changeset, :action, :insert)
        recipe_form = Phoenix.Component.to_form(recipe_changeset)

        current_recipe =
          case Recepies.get_active_recipe(variant) do
            nil -> nil
            recipe -> Recepies.get_recipe!(recipe.id)
          end

        recipe_variant_options =
          Recepies.variants_with_recipes_select_options()
          |> Enum.reject(fn {_label, vid} -> vid == variant.id end)

        ingredient_options_raw = Inventory.ingredient_options_with_units()

        ingredient_options =
          Enum.map(ingredient_options_raw, fn {name, code, _unit} -> {name, code} end)

        ingredient_options_json =
          Jason.encode!(
            Enum.map(ingredient_options_raw, fn {name, code, unit} -> [name, code, unit] end)
          )

        changeset = ProductVariant.changeset(variant, %{})

        render(conn, :edit,
          variant: variant,
          product: variant.product,
          changeset: changeset,
          action: dp(conn, "/products/#{product_id}/variants/#{variant_id}"),
          current_recipe: current_recipe,
          recipe_form: recipe_form,
          recipe_action: dp(conn, "/products/#{product_id}/variants/#{variant_id}/recipe"),
          recipe_variant_options: recipe_variant_options,
          ingredient_options: ingredient_options,
          ingredient_options_json: ingredient_options_json,
          copied_from_variant: nil
        )
    end
  end

  # Build default recipe assigns for error re-renders (update/2 failure).
  # Uses current recipe if available; otherwise empty form with one blank line.
  defp build_default_recipe_assigns(conn, variant, product_id) do
    today_mx =
      NaiveDateTime.utc_now() |> NaiveDateTime.add(-6 * 3600, :second) |> NaiveDateTime.to_date()

    current_recipe =
      case Recepies.get_active_recipe(variant) do
        nil -> nil
        recipe -> Recepies.get_recipe!(recipe.id)
      end

    recipe_attrs =
      if current_recipe != nil do
        new_effective_date =
          if Date.compare(current_recipe.effective_date, today_mx) != :lt do
            Date.add(current_recipe.effective_date, 1)
          else
            today_mx
          end

        %{
          "effective_date" => Date.to_iso8601(new_effective_date),
          "recipe_lines" =>
            Enum.map(current_recipe.recipe_lines || [], fn line ->
              %{
                "ingredient_code" => line.ingredient_code,
                "quantity" => Decimal.to_string(line.quantity),
                "comment" => line.comment
              }
            end)
        }
      else
        %{"recipe_lines" => [%{}]}
      end

    recipe_changeset = Recepies.change_recipe(%Recipe{}, recipe_attrs)
    recipe_form = Phoenix.Component.to_form(recipe_changeset)

    recipe_variant_options =
      Recepies.variants_with_recipes_select_options()
      |> Enum.reject(fn {_label, vid} -> vid == variant.id end)

    ingredient_options_raw = Inventory.ingredient_options_with_units()

    ingredient_options =
      Enum.map(ingredient_options_raw, fn {name, code, _unit} -> {name, code} end)

    ingredient_options_json =
      Jason.encode!(
        Enum.map(ingredient_options_raw, fn {name, code, unit} -> [name, code, unit] end)
      )

    [
      current_recipe: current_recipe,
      recipe_form: recipe_form,
      recipe_action: dp(conn, "/products/#{product_id}/variants/#{variant.id}/recipe"),
      recipe_variant_options: recipe_variant_options,
      ingredient_options: ingredient_options,
      ingredient_options_json: ingredient_options_json,
      copied_from_variant: nil
    ]
  end

  # Convert price in pesos (string) to price_cents (integer).
  # Uses Float.parse/1 instead of String.to_float/1 so that whole numbers
  # like "120" are accepted without requiring a decimal point.
  defp parse_price(%{"price" => price} = params) when is_binary(price) and price != "" do
    case price |> String.trim() |> String.replace(",", ".") |> Float.parse() do
      {f, _} ->
        params |> Map.delete("price") |> Map.put("price_cents", round(f * 100))

      :error ->
        Map.delete(params, "price")
    end
  end

  defp parse_price(params), do: Map.delete(params, "price")
end

defmodule LedgrWeb.Domains.MrMunchMe.VariantHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents
  import Phoenix.Naming

  embed_templates "variant_html/*"
end
