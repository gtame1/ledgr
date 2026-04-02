defmodule LedgrWeb.Domains.MrMunchMe.InventoryController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Core.Accounting

  def index(conn, _params) do
    # Batch-load all inventory values in 4 queries instead of 4 × N
    values_map = Inventory.batch_inventory_values()

    stock_items =
      Inventory.list_stock_items()
      |> Enum.filter(fn stock -> stock.quantity_on_hand > 0 end)
      |> Enum.map(fn stock ->
        total_value_cents = Map.get(values_map, {stock.ingredient_id, stock.location_id}, 0)
        Map.put(stock, :total_value_cents, total_value_cents)
      end)

    # Group stock items by inventory type
    stock_by_type =
      stock_items
      |> Enum.group_by(fn stock ->
        Inventory.inventory_type(stock.ingredient.code)
      end)

    # Handle all_dates parameter
    {date_from_param, date_to_param} =
      if conn.params["all_dates"] == "true" do
        {earliest_date, latest_date} = Inventory.movement_date_range()
        {
          if(earliest_date, do: Date.to_iso8601(earliest_date), else: nil),
          if(latest_date, do: Date.to_iso8601(latest_date), else: nil)
        }
      else
        {conn.params["date_from"], conn.params["date_to"]}
      end

    # Check if we have search/filter params
    has_filters =
      conn.params["search"] != nil ||
      conn.params["movement_type"] != nil ||
      conn.params["ingredient_id"] != nil ||
      conn.params["from_location_id"] != nil ||
      conn.params["to_location_id"] != nil ||
      date_from_param != nil ||
      date_to_param != nil ||
      conn.params["all_dates"] == "true"

    {recent_movements, movements_limit, has_more} =
      if has_filters do
        # Use search/filter function
        search_opts = [
          search: conn.params["search"],
          movement_type: conn.params["movement_type"],
          ingredient_code: conn.params["ingredient_id"],  # ingredient_id param actually contains the code
          from_location_id: parse_integer(conn.params["from_location_id"]),
          to_location_id: parse_integer(conn.params["to_location_id"]),
          date_from: parse_date(date_from_param),
          date_to: parse_date(date_to_param),
          limit: 500  # Higher limit for filtered results
        ]

        movements = Inventory.search_movements(search_opts)
        {movements, length(movements), false}
      else
        # Use default recent movements with limit
        limit = case Integer.parse(conn.params["movements_limit"] || "10") do
          {parsed_limit, _} when parsed_limit > 0 -> parsed_limit
          _ -> 10
        end

        movements = Inventory.list_recent_movements(limit)
        has_more = Inventory.has_more_movements?(limit)
        {movements, limit, has_more}
      end

    total_value_cents = stock_items |> Enum.reduce(0, fn s, acc -> acc + (s.total_value_cents || 0) end)
    ingredient_options = Inventory.ingredient_select_options()
    location_options = Inventory.location_select_options()
    {earliest_date, latest_date} = Inventory.movement_date_range()

    # Build filter params for template
    filter_params = %{
      search: conn.params["search"],
      movement_type: conn.params["movement_type"],
      ingredient_id: conn.params["ingredient_id"],
      from_location_id: conn.params["from_location_id"],
      to_location_id: conn.params["to_location_id"],
      date_from: date_from_param || "",
      date_to: date_to_param || ""
    }

    render(conn, :index,
      stock_items: stock_items,
      stock_by_type: stock_by_type,
      recent_movements: recent_movements,
      movements_limit: movements_limit,
      has_more_movements: has_more,
      total_value_cents: total_value_cents,
      ingredient_options: ingredient_options,
      location_options: location_options,
      filter_params: filter_params,
      earliest_date: earliest_date,
      latest_date: latest_date
    )
  end

  # Helper to parse integer from string, returns nil if invalid
  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil
  defp parse_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
  end
  defp parse_integer(int) when is_integer(int), do: int
  defp parse_integer(_), do: nil

  # Helper to parse date from string, returns nil if invalid
  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end
  defp parse_date(%Date{} = date), do: date
  defp parse_date(_), do: nil

  # -------- New purchase form --------

  def new_purchase(conn, _params) do
    changeset = Inventory.change_purchase_list_form(%{})
    form = Phoenix.Component.to_form(changeset)
    ingredient_options = Inventory.ingredient_select_options()
    # Convert tuples to lists for JSON encoding
    ingredient_options_list = Enum.map(ingredient_options, fn {name, code} -> [name, code] end)

    render(conn, :new_purchase,
      form: form,
      ingredient_options: ingredient_options,
      ingredient_options_json: Jason.encode!(ingredient_options_list),
      location_options: Inventory.location_select_options(),
      ingredient_infos: Inventory.ingredient_quick_infos(),
      paid_from_account_options: Accounting.cash_or_payable_account_options(),
      purchase_date: today_mx()
    )
  end

  def create_purchase(conn, %{"purchase_list_form" => purchase_params}) do
    handle_purchase_submission(conn, purchase_params)
  end

  # keep the catch-all for safety / debug if you want
  def create_purchase(conn, params) do
    require Logger
    Logger.error("create_purchase received unexpected params: #{inspect(params)}")

    conn
    |> put_flash(:error, "Invalid form data. Please try again.")
    |> redirect(to: dp(conn, "/inventory/purchases/new"))
  end

  defp handle_purchase_submission(conn, purchase_params) do
    require Logger
    Logger.debug("📨 handle_purchase_submission called with: #{inspect(purchase_params)}")

    case Inventory.create_purchase_list(purchase_params) do
      {:ok, _result} ->
        Logger.debug("✅ Inventory.create_purchase_list/1 succeeded")

        conn
        |> put_flash(:info, "Purchase list recorded successfully.")
        |> redirect(to: dp(conn, "/inventory"))

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.error("❌ Inventory.create_purchase_list/1 returned changeset error: #{inspect(changeset.errors)}")

        changeset = %{changeset | action: :insert}
        form = Phoenix.Component.to_form(changeset)

        ingredient_options = Inventory.ingredient_select_options()
        ingredient_options_list =
          Enum.map(ingredient_options, fn {name, code} -> [name, code] end)

        render(conn, :new_purchase,
          form: form,
          ingredient_options: ingredient_options,
          ingredient_options_json: Jason.encode!(ingredient_options_list),
          location_options: Inventory.location_select_options(),
          ingredient_infos: Inventory.ingredient_quick_infos(),
          paid_from_account_options: Accounting.cash_or_payable_account_options(),
          purchase_date: purchase_params["purchase_date"] || today_mx()
        )
    end
  end

  # -------- New manual movement (usage / transfer) --------

  def new_movement(conn, _params) do
    changeset = Inventory.change_movement_list_form(%{})

    form = Phoenix.Component.to_form(changeset)
    ingredient_options = Inventory.ingredient_select_options()
    # Convert tuples to lists for JSON encoding
    ingredient_options_list = Enum.map(ingredient_options, fn {name, code} -> [name, code] end)

    render(conn, :new_movement,
      form: form,
      ingredient_options: ingredient_options,
      ingredient_options_json: Jason.encode!(ingredient_options_list),
      location_options: Inventory.location_select_options(),
      ingredient_infos: Inventory.ingredient_quick_infos(),
      ingredient_location_stock: Inventory.ingredient_location_stock(),
      movement_date: today_mx()
    )
  end

  def create_movement(conn, %{"movement_list_form" => movement_params}) do
    handle_movement_submission(conn, movement_params)
  end

  # keep the catch-all for safety / debug if you want
  def create_movement(conn, params) do
    require Logger
    Logger.error("create_movement received unexpected params: #{inspect(params)}")

    conn
    |> put_flash(:error, "Invalid form data. Please try again.")
    |> redirect(to: dp(conn, "/inventory/movements/new"))
  end

  defp handle_movement_submission(conn, movement_params) do
    require Logger
    Logger.debug("📨 handle_movement_submission called with: #{inspect(movement_params)}")

    case Inventory.create_movement_list(movement_params) do
      {:ok, _result} ->
        Logger.debug("✅ Inventory.create_movement_list/1 succeeded")

        conn
        |> put_flash(:info, "Movement list recorded successfully.")
        |> redirect(to: dp(conn, "/inventory"))

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.error("❌ Inventory.create_movement_list/1 returned changeset error: #{inspect(changeset.errors)}")

        changeset = %{changeset | action: :insert}
        form = Phoenix.Component.to_form(changeset)

        ingredient_options = Inventory.ingredient_select_options()
        ingredient_options_list =
          Enum.map(ingredient_options, fn {name, code} -> [name, code] end)

        render(conn, :new_movement,
          form: form,
          ingredient_options: ingredient_options,
          ingredient_options_json: Jason.encode!(ingredient_options_list),
          location_options: Inventory.location_select_options(),
          ingredient_infos: Inventory.ingredient_quick_infos(),
          ingredient_location_stock: Inventory.ingredient_location_stock(),
          movement_date: movement_params["movement_date"] || today_mx()
        )

      other ->
        Logger.error("❌ Inventory.create_movement_list/1 returned unexpected: #{inspect(other)}")

        conn
        |> put_flash(:error, "Unexpected error while saving movement list.")
        |> redirect(to: dp(conn, "/inventory/movements/new"))
    end
  end

  def requirements(conn, _params) do
    requirements = Inventory.required_ingredients_for_new_orders()

    render(conn, :requirements,
      requirements: requirements
    )
  end

  # -------- Edit/Delete purchase --------

  def edit_purchase(conn, %{"id" => id}) do
    movement = Inventory.get_movement!(id)

    if movement.movement_type != "purchase" do
      conn
      |> put_flash(:error, "This movement is not a purchase.")
      |> redirect(to: dp(conn, "/inventory"))
    else
      # Convert movement to form attrs
      total_cost_pesos =
        movement.total_cost_cents
        |> Decimal.new()
        |> Decimal.div(Decimal.new(100))
        |> Decimal.to_string()

      attrs = %{
        "ingredient_code" => movement.ingredient.code,
        "location_code" => movement.to_location.code,
        "quantity" => movement.quantity,
        "total_cost_pesos" => total_cost_pesos,
        "paid_from_account_id" => to_string(movement.paid_from_account_id),
        "purchase_date" => movement.movement_date
      }

      changeset = Inventory.change_purchase_form(attrs)

      render(conn, :edit_purchase,
        changeset: changeset,
        movement: movement,
        ingredient_options: Inventory.ingredient_select_options(),
        location_options: Inventory.location_select_options(),
        ingredient_infos: Inventory.ingredient_quick_infos(),
        paid_from_account_options: Accounting.cash_or_payable_account_options(),
        purchase_date: movement.movement_date
      )
    end
  end

  def update_purchase(conn, %{"id" => id, "purchase" => purchase_params}) do
    case Inventory.update_purchase(id, purchase_params) do
      {:ok, _result} ->
        conn
        |> put_flash(:info, "Purchase updated successfully.")
        |> redirect(to: dp(conn, "/inventory"))

      {:error, :not_a_purchase} ->
        conn
        |> put_flash(:error, "This movement is not a purchase.")
        |> redirect(to: dp(conn, "/inventory"))

      {:error, changeset} ->
        movement = Inventory.get_movement!(id)

        render(conn, :edit_purchase,
          changeset: changeset,
          movement: movement,
          ingredient_options: Inventory.ingredient_select_options(),
          location_options: Inventory.location_select_options(),
          ingredient_infos: Inventory.ingredient_quick_infos(),
          paid_from_account_options: Accounting.cash_or_payable_account_options(),
          purchase_date: purchase_params["purchase_date"] || movement.movement_date
        )
    end
  end

  def delete_purchase(conn, %{"id" => id}) do
    case Inventory.delete_purchase(id) do
      {:ok, _result} ->
        conn
        |> put_flash(:info, "Purchase deleted successfully.")
        |> redirect(to: dp(conn, "/inventory#recent_movements_card"))

      {:error, :not_a_purchase} ->
        conn
        |> put_flash(:error, "This movement is not a purchase.")
        |> redirect(to: dp(conn, "/inventory"))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to delete purchase.")
        |> redirect(to: dp(conn, "/inventory"))
    end
  end

  def return_purchase(conn, %{"id" => id}) do
    return_date = case conn.params["return_date"] do
      nil -> nil
      date_str when is_binary(date_str) ->
        case Date.from_iso8601(date_str) do
          {:ok, date} -> date
          _ -> nil
        end
      _ -> nil
    end

    note = conn.params["note"]

    case Inventory.return_purchase(id, return_date, note) do
      {:ok, _result} ->
        conn
        |> put_flash(:info, "Purchase returned successfully.")
        |> redirect(to: dp(conn, "/inventory#recent_movements_card"))

      {:error, :not_a_purchase} ->
        conn
        |> put_flash(:error, "This movement is not a purchase.")
        |> redirect(to: dp(conn, "/inventory"))

      {:error, {:insufficient_quantity, message}} ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: dp(conn, "/inventory"))

      {:error, reason} when is_binary(reason) ->
        conn
        |> put_flash(:error, reason)
        |> redirect(to: dp(conn, "/inventory"))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to return purchase.")
        |> redirect(to: dp(conn, "/inventory"))
    end
  end

  # -------- Edit/Delete movement (transfer/usage/write_off) --------

  def edit_movement(conn, %{"id" => id}) do
    movement = Inventory.get_movement!(id)

    if movement.movement_type == "transfer" do
      # Convert movement to form attrs
      attrs = %{
        "movement_type" => movement.movement_type,
        "ingredient_code" => movement.ingredient.code,
        "from_location_code" => movement.from_location && movement.from_location.code,
        "to_location_code" => movement.to_location && movement.to_location.code,
        "quantity" => movement.quantity,
        "movement_date" => movement.movement_date,
        "note" => movement.note
      }

      changeset = Inventory.change_movement_form(attrs)

      render(conn, :edit_movement,
        changeset: changeset,
        movement: movement,
        ingredient_options: Inventory.ingredient_select_options(),
        location_options: Inventory.location_select_options(),
        movement_date: movement.movement_date
      )
    else
      conn
      |> put_flash(:error, "Only transfers can be edited.")
      |> redirect(to: dp(conn, "/inventory"))
    end
  end

  def update_movement(conn, %{"id" => id, "movement" => movement_params}) do
    movement = Inventory.get_movement!(id)

    if movement.movement_type != "transfer" do
      conn
      |> put_flash(:error, "Only transfers can be updated.")
      |> redirect(to: dp(conn, "/inventory"))
    else
      case Inventory.update_transfer(id, movement_params) do
        {:ok, _result} ->
          conn
          |> put_flash(:info, "Transfer updated successfully.")
          |> redirect(to: dp(conn, "/inventory"))

        {:error, :not_a_transfer} ->
          conn
          |> put_flash(:error, "This movement is not a transfer.")
          |> redirect(to: dp(conn, "/inventory"))

        {:error, changeset} ->
          changeset = %{changeset | action: :update}

          render(conn, :edit_movement,
            changeset: changeset,
            movement: movement,
            ingredient_options: Inventory.ingredient_select_options(),
            location_options: Inventory.location_select_options(),
            movement_date: movement_params["movement_date"] || movement.movement_date
          )
      end
    end
  end

  def delete_movement(conn, %{"id" => id}) do
    movement = Inventory.get_movement!(id)

    case movement.movement_type do
      "transfer" ->
        case Inventory.delete_transfer(id) do
          {:ok, _result} ->
            conn
            |> put_flash(:info, "Transfer deleted successfully.")
            |> redirect(to: dp(conn, "/inventory#recent_movements_card"))

          {:error, :not_a_transfer} ->
            conn
            |> put_flash(:error, "This movement is not a transfer.")
            |> redirect(to: dp(conn, "/inventory"))

          {:error, _reason} ->
            conn
            |> put_flash(:error, "Failed to delete transfer.")
            |> redirect(to: dp(conn, "/inventory"))
        end

      _ ->
        conn
        |> put_flash(:error, "Only transfers can be deleted.")
        |> redirect(to: dp(conn, "/inventory"))
    end
  end

end


defmodule LedgrWeb.Domains.MrMunchMe.InventoryHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents

  embed_templates "inventory_html/*"
end
