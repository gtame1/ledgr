defmodule LedgrWeb.ReconciliationController do
  use LedgrWeb, :controller
  require Logger

  alias Ledgr.Core.Reconciliation
  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Domains.MrMunchMe.Reconciliation, as: InventoryReconciliation
  alias Ledgr.Core.Settings

  # ---------- Accounting Reconciliation ----------

  def accounting_index(conn, params) do
    as_of =
      case Map.get(params, "as_of") do
        nil -> domain_today()
        "" -> domain_today()
        date_str -> Date.from_iso8601!(date_str)
      end

    accounts = Reconciliation.list_accounts_for_reconciliation(as_of)

    last_reconciled_date = Settings.get_last_reconciled_date()

    template =
      if Ledgr.Domain.current() == Ledgr.Domains.HelloDoctor,
        do: :hello_doctor_accounting_index,
        else: :accounting_index

    render(conn, template,
      accounts: accounts,
      as_of: as_of,
      last_reconciled_date: last_reconciled_date
    )
  end

  def accounting_adjust(conn, params) do
    account_id = params["account_id"]
    actual_balance_str = params["actual_balance"]
    date_str = params["adjustment_date"]
    description = params["description"]

    if is_nil(account_id) or is_nil(actual_balance_str) or is_nil(date_str) do
      conn
      |> put_flash(:error, "Missing required fields")
      |> redirect(to: dp(conn, "/reconciliation/accounting"))
    else
      _account = Accounting.get_account!(account_id)

      actual_balance =
        case Float.parse(actual_balance_str) do
          {float_val, _} ->
            float_val

          :error ->
            # Try parsing as integer and converting to float
            case Integer.parse(actual_balance_str) do
              {int_val, _} -> int_val * 1.0
              :error -> raise ArgumentError, "Invalid balance value: #{actual_balance_str}"
            end
        end

      adjustment_date = Date.from_iso8601!(date_str)

      case Reconciliation.create_account_reconciliation(
             account_id,
             actual_balance,
             adjustment_date,
             description
           ) do
        {:ok, _journal_entry} ->
          conn
          |> put_flash(:info, "Reconciliation adjustment created successfully")
          |> redirect(to: dp(conn, "/reconciliation/accounting"))

        {:error, reason} when is_binary(reason) ->
          conn
          |> put_flash(:error, reason)
          |> redirect(to: dp(conn, "/reconciliation/accounting"))

        {:error, changeset} ->
          error_msg =
            case changeset.errors do
              [] -> "Failed to create adjustment"
              errors -> "Failed to create adjustment: #{inspect(errors)}"
            end

          conn
          |> put_flash(:error, error_msg)
          |> redirect(to: dp(conn, "/reconciliation/accounting"))
      end
    end
  end

  def accounting_reconcile_all(conn, params) do
    date_str = params["as_of"]
    accounts_params = params["accounts"] || %{}

    as_of =
      case date_str do
        nil -> domain_today()
        "" -> domain_today()
        d -> Date.from_iso8601!(d)
      end

    adjustment_count =
      Enum.reduce(accounts_params, 0, fn {account_id, actual_balance_str}, count ->
        case Float.parse(actual_balance_str) do
          {actual_balance, _} ->
            case Reconciliation.create_account_reconciliation(account_id, actual_balance, as_of) do
              {:ok, _journal_entry} -> count + 1
              {:error, _reason} -> count
            end

          :error ->
            count
        end
      end)

    # Always save the reconciled date, even if no adjustments were needed
    Settings.set_last_reconciled_date(as_of)

    flash_msg =
      case adjustment_count do
        0 -> "All accounts reconciled — no adjustments needed."
        1 -> "Reconciliation complete — 1 adjustment created."
        n -> "Reconciliation complete — #{n} adjustments created."
      end

    conn
    |> put_flash(:info, flash_msg)
    |> redirect(to: dp(conn, "/reconciliation/accounting?as_of=#{as_of}"))
  end

  # ---------- Inventory Reconciliation ----------

  def inventory_index(conn, _params) do
    inventory_items = InventoryReconciliation.list_inventory_for_reconciliation()
    last_reconciled_date = Settings.get_last_inventory_reconciled_date()
    locations = Inventory.list_locations()

    render(conn, :inventory_index,
      inventory_items: inventory_items,
      last_reconciled_date: last_reconciled_date,
      locations: locations
    )
  end

  def inventory_adjust(conn, params) do
    Logger.info("Inventory adjust called with params: #{inspect(params)}")

    ingredient_id = params["ingredient_id"]
    location_id = params["location_id"]
    actual_quantity_str = params["actual_quantity"]
    date_str = params["adjustment_date"]
    description = params["description"]

    Logger.info(
      "Parsed values - ingredient_id: #{inspect(ingredient_id)}, location_id: #{inspect(location_id)}, actual_quantity_str: #{inspect(actual_quantity_str)}, date_str: #{inspect(date_str)}"
    )

    if is_nil(ingredient_id) or is_nil(location_id) or is_nil(actual_quantity_str) or
         is_nil(date_str) do
      Logger.warning("Missing required fields in inventory adjust")

      conn
      |> put_flash(:error, "Missing required fields")
      |> redirect(to: dp(conn, "/reconciliation/inventory"))
    else
      try do
        actual_quantity = String.to_integer(actual_quantity_str)
        adjustment_date = Date.from_iso8601!(date_str)

        Logger.info(
          "Calling create_inventory_reconciliation with ingredient_id: #{ingredient_id}, location_id: #{location_id}, actual_quantity: #{actual_quantity}, adjustment_date: #{adjustment_date}"
        )

        case InventoryReconciliation.create_inventory_reconciliation(
               ingredient_id,
               location_id,
               actual_quantity,
               adjustment_date,
               description
             ) do
          {:ok, result} ->
            Logger.info("Inventory reconciliation successful: #{inspect(result)}")

            conn
            |> put_flash(:info, "Inventory reconciliation adjustment created successfully")
            |> redirect(to: dp(conn, "/reconciliation/inventory"))

          {:error, reason} when is_binary(reason) ->
            Logger.warning("Inventory reconciliation error (string): #{reason}")

            conn
            |> put_flash(:error, reason)
            |> redirect(to: dp(conn, "/reconciliation/inventory"))

          {:error, changeset} ->
            Logger.error(
              "Inventory reconciliation error (changeset): #{inspect(changeset.errors)}"
            )

            error_msg =
              case changeset.errors do
                [] -> "Failed to create adjustment"
                errors -> "Failed to create adjustment: #{inspect(errors)}"
              end

            conn
            |> put_flash(:error, error_msg)
            |> redirect(to: dp(conn, "/reconciliation/inventory"))
        end
      rescue
        e ->
          Logger.error(
            "Exception in inventory_adjust: #{inspect(e)} - #{Exception.format(:error, e, __STACKTRACE__)}"
          )

          conn
          |> put_flash(:error, "Error: #{Exception.message(e)}")
          |> redirect(to: dp(conn, "/reconciliation/inventory"))
      end
    end
  end

  def inventory_reconcile_all(conn, params) do
    items_params = params["items"] || %{}
    today = domain_today()

    adjustment_count =
      Enum.reduce(items_params, 0, fn {key, actual_quantity_str}, count ->
        case String.split(key, "-", parts: 2) do
          [ingredient_id, location_id] ->
            case Integer.parse(actual_quantity_str) do
              {actual_quantity, _} ->
                case InventoryReconciliation.create_inventory_reconciliation(
                       ingredient_id,
                       location_id,
                       actual_quantity,
                       today
                     ) do
                  {:ok, _result} -> count + 1
                  {:error, _reason} -> count
                end

              :error ->
                count
            end

          _ ->
            count
        end
      end)

    # Always save the reconciled date, even if no adjustments were needed
    Settings.set_last_inventory_reconciled_date(today)

    flash_msg =
      case adjustment_count do
        0 -> "All inventory reconciled — no adjustments needed."
        1 -> "Reconciliation complete — 1 adjustment created."
        n -> "Reconciliation complete — #{n} adjustments created."
      end

    conn
    |> put_flash(:info, flash_msg)
    |> redirect(to: dp(conn, "/reconciliation/inventory"))
  end

  def inventory_quick_transfer(conn, params) do
    ingredient_code = params["ingredient_code"]
    from_location_code = params["from_location_code"]
    to_location_code = params["to_location_code"]
    quantity_str = params["quantity"]

    with {quantity, _} when quantity > 0 <- Integer.parse(quantity_str || ""),
         true <- from_location_code != to_location_code do
      case Inventory.transfer(
             ingredient_code,
             from_location_code,
             to_location_code,
             quantity,
             domain_today()
           ) do
        {:ok, _result} ->
          conn
          |> put_flash(
            :info,
            "Transferred #{quantity} #{ingredient_code} from #{from_location_code} to #{to_location_code}"
          )
          |> redirect(to: dp(conn, "/reconciliation/inventory"))

        {:error, reason} ->
          conn
          |> put_flash(:error, "Transfer failed: #{inspect(reason)}")
          |> redirect(to: dp(conn, "/reconciliation/inventory"))
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid transfer — check quantity and locations")
        |> redirect(to: dp(conn, "/reconciliation/inventory"))
    end
  end

  defp domain_today, do: today_mx()
end

defmodule LedgrWeb.ReconciliationHTML do
  use LedgrWeb, :html

  import LedgrWeb.CoreComponents

  embed_templates "reconciliation_html/*"
end
