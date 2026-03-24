defmodule LedgrWeb.Domains.MrMunchMe.OrderController do
  use LedgrWeb, :controller

  require Logger

  alias Ledgr.Domains.MrMunchMe.Orders
  alias Ledgr.Domains.MrMunchMe.Orders.{Order, OrderPayment}
  alias Ledgr.Core.{Accounting, Customers, Partners}
  alias Ledgr.Domains.MrMunchMe.OrderAccounting
  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Repo
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, params) do
    # 1) Apply defaults directly to params
    params =
      params
      |> Map.put_new("sort_by", "delivery_date")
      |> Map.put_new("sort_dir", "asc")

    # 2) Use these params for the query
    all_orders = Orders.list_orders(params)

    # Calculate payment summaries — orders already have :order_payments preloaded, no extra queries
    orders_with_payment_status =
      Enum.map(all_orders, fn order ->
        payment_summary = Orders.payment_summary_from_preloaded(order)
        Map.put(order, :payment_summary, payment_summary)
      end)

    # 3) Separate active orders from completed (delivered & paid) orders
    {active_orders, _completed_orders} =
      Enum.split_with(orders_with_payment_status, fn order ->
        !(order.status == "delivered" && order.payment_summary.fully_paid?)
      end)

    # 4) Get completed orders with pagination
    # We show all completed orders up to the current offset + limit
    completed_limit = 10
    completed_offset =
      case params["completed_offset"] do
        nil -> 0
        "" -> 0
        val -> String.to_integer(val)
      end

    # Load all completed orders from 0 to offset+limit
    total_to_load = completed_offset + completed_limit
    completed_orders = Orders.list_delivered_and_paid_orders(total_to_load, 0)

    # Calculate payment summaries — orders already have :order_payments preloaded
    completed_orders_with_payment_status =
      Enum.map(completed_orders, fn order ->
        payment_summary = Orders.payment_summary_from_preloaded(order)
        Map.put(order, :payment_summary, payment_summary)
      end)

    # Check if there are more completed orders by trying to load one more
    # If we got exactly what we asked for, there might be more
    has_more_completed = length(completed_orders_with_payment_status) >= total_to_load

    # 5) Get canceled orders (finished orders)
    canceled_limit = 50
    canceled_offset =
      case params["canceled_offset"] do
        nil -> 0
        "" -> 0
        val -> String.to_integer(val)
      end

    total_canceled_to_load = canceled_offset + canceled_limit
    canceled_orders = Orders.list_canceled_orders(total_canceled_to_load, 0)

    # Calculate payment summaries — orders already have :order_payments preloaded
    canceled_orders_with_payment_status =
      Enum.map(canceled_orders, fn order ->
        payment_summary = Orders.payment_summary_from_preloaded(order)
        Map.put(order, :payment_summary, payment_summary)
      end)

    has_more_canceled = length(canceled_orders_with_payment_status) >= total_canceled_to_load

    # 6) Build filters map from the same params (so UI & query are in sync)
    filters = %{
      status: params["status"] || "",
      delivery_type: params["delivery_type"] || "",
      product_id: params["product_id"] || "",
      prep_location_id: params["prep_location_id"] || "",
      date_from: params["date_from"] || "",
      date_to: params["date_to"] || "",
      sort_by: params["sort_by"],
      sort_dir: params["sort_dir"]
    }

    render(conn, :index,
      orders: active_orders,
      completed_orders: completed_orders_with_payment_status,
      completed_offset: completed_offset,
      has_more_completed: has_more_completed,
      canceled_orders: canceled_orders_with_payment_status,
      canceled_offset: canceled_offset,
      has_more_canceled: has_more_canceled,
      filters: filters,
      product_filter_options: Orders.product_select_options(),
      location_filter_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id})
    )
  end

  def new(conn, _params) do
    changeset = Orders.change_order(%Order{})
    default_fee_cents = OrderAccounting.shipping_fee_cents()

    render(conn, :new,
      changeset: changeset,
      action: dp(conn, "/orders"),
      variant_options: Orders.variant_select_options(),
      variant_prices: variant_price_map(),
      shipping_fee_cents: default_fee_cents,
      default_shipping_fee_pesos: format_pesos(default_fee_cents),
      location_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id}),
      customer_options: Customers.customer_select_options()
    )
  end

  def create(conn, %{"order" => params}) do
    params = parse_shipping_fee(params)

    case Orders.create_order(params) do
      {:ok, order} ->
        conn
        |> put_flash(:info, "Order created.")
        |> redirect(to: dp(conn, "/orders/#{order.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :insert)
        default_fee_cents = OrderAccounting.shipping_fee_cents()

        render(conn, :new,
          changeset: changeset,
          action: dp(conn, "/orders"),
          variant_options: Orders.variant_select_options(),
          variant_prices: variant_price_map(),
          shipping_fee_cents: default_fee_cents,
          default_shipping_fee_pesos: format_pesos(default_fee_cents),
          location_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id}),
          customer_options: Customers.customer_select_options()
        )

      {:error, _reason} ->
        changeset =
          %Order{}
          |> Order.changeset(params)
          |> Map.put(:action, :insert)

        default_fee_cents = OrderAccounting.shipping_fee_cents()

        conn
        |> put_flash(:error, "There was a problem creating this order. Please check the form and try again.")
        |> render(:new,
          changeset: changeset,
          action: dp(conn, "/orders"),
          variant_options: Orders.variant_select_options(),
          variant_prices: variant_price_map(),
          shipping_fee_cents: default_fee_cents,
          default_shipping_fee_pesos: format_pesos(default_fee_cents),
          location_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id}),
          customer_options: Customers.customer_select_options()
        )
    end
  end

  def show(conn, %{"id" => id}) do
    order = Orders.get_order!(id)
    payments = Orders.list_payments_for_order(order.id)
    payment_summary = Orders.payment_summary(order)

    # Get recipe ingredients for editing (only relevant for new_order status)
    recipe_ingredients =
      if order.status == "new_order" do
        recipe_date = order.delivery_date || Date.utc_today()
        Inventory.Recepies.recipe_for_variant(order.variant, recipe_date)
      else
        []
      end

    # Get current order ingredients (custom overrides), or fall back to recipe
    current_ingredients =
      case order.order_ingredients do
        ingredients when is_list(ingredients) and ingredients != [] ->
          Enum.map(ingredients, fn oi ->
            %{ingredient_code: oi.ingredient_code, quantity: Decimal.to_float(oi.quantity)}
          end)

        _ ->
          recipe_ingredients
      end

    # Get ingredient options for the select dropdown
    ingredient_options = Inventory.list_ingredients() |> Enum.map(&{&1.name <> " (#{&1.code})", &1.code})

    render(conn, :show,
      order: order,
      payments: payments,
      payment_summary: payment_summary,
      recipe_ingredients: recipe_ingredients,
      current_ingredients: current_ingredients,
      ingredient_options: ingredient_options
    )
  end

  def edit(conn, %{"id" => id}) do
    order = Orders.get_order!(id)
    changeset = Orders.change_order(order)
    default_fee_cents = OrderAccounting.shipping_fee_cents()
    current_fee_pesos = format_pesos(order.shipping_fee_cents || default_fee_cents)

    render(conn, :edit,
      order: order,
      changeset: changeset,
      variant_options: Orders.variant_select_options(),
      location_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id}),
      customer_options: Customers.customer_select_options(),
      default_shipping_fee_pesos: current_fee_pesos
    )
  end

  def update(conn, %{"id" => id, "order" => order_params}) do
    order = Orders.get_order!(id) |> Repo.preload([:prep_location])
    order_params = parse_shipping_fee(order_params)

    case Orders.update_order(order, order_params) do
      {:ok, order} ->
        conn
        |> put_flash(:info, "Order updated successfully.")
        |> redirect(to: dp(conn, "/orders/#{order.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        default_fee_cents = OrderAccounting.shipping_fee_cents()
        current_fee_pesos = format_pesos(order.shipping_fee_cents || default_fee_cents)

        render(conn, :edit,
          order: order,
          changeset: changeset,
          variant_options: Orders.variant_select_options(),
          location_options: Inventory.list_locations() |> Enum.map(&{&1.name, &1.id}),
          customer_options: Customers.customer_select_options(),
          default_shipping_fee_pesos: current_fee_pesos
        )
    end
  end

  def update_ingredients(conn, %{"id" => id, "ingredients" => ingredients_params}) do
    order = Orders.get_order!(id)

    # Convert params to list format expected by update_order_ingredients
    ingredients_list =
      ingredients_params
      |> Enum.map(fn {_key, attrs} ->
        # Convert quantity string to Decimal
        quantity = case attrs["quantity"] do
          qty when is_binary(qty) and qty != "" ->
            case Decimal.parse(qty) do
              {decimal, _} -> decimal
              :error -> Decimal.new("0")
            end
          _ -> Decimal.new("0")
        end

        %{
          "ingredient_code" => attrs["ingredient_code"],
          "quantity" => quantity,
          "location_code" => attrs["location_code"] || (order.prep_location && order.prep_location.code) || "CASA_AG"
        }
      end)
      |> Enum.filter(fn attrs -> attrs["ingredient_code"] != "" and attrs["ingredient_code"] != nil end)

    case Orders.update_order_ingredients(order, ingredients_list) do
      {:ok, updated_order} ->
        conn
        |> put_flash(:info, "Order ingredients updated successfully.")
        |> redirect(to: dp(conn, "/orders/#{updated_order.id}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to update ingredients: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/orders/#{order.id}"))
    end
  end

  def update_status(conn, %{"id" => id, "status" => %{"status" => new_status}}) do
    order = Orders.get_order!(id)

    case Orders.update_order_status(order, new_status) do
      {:ok, _updated} ->
        conn
        |> put_flash(:info, "Order status updated to #{new_status}.")
        |> redirect(to: dp(conn, "/orders"))

      {:error, :invalid_status} ->
        conn
        |> put_flash(:error, "Invalid status change.")
        |> redirect(to: dp(conn, "/orders/#{order.id}"))

      {:error, %Ecto.Changeset{} = _changeset} ->
        # This would be rare, but handle it nicely
        conn
        |> put_flash(:error, "Could not update status.")
        |> redirect(to: dp(conn, "/orders/#{order.id}"))
    end
  end

  def new_payment(conn, %{"id" => id}) do
    order = Orders.get_order!(id)
    payment_summary = Orders.payment_summary(order)

    changeset =
      Orders.change_order_payment(%OrderPayment{
        order_id: order.id,
        payment_date: Date.utc_today()
      })

    render(conn, :new_payment,
      order: order,
      payment_summary: payment_summary,
      changeset: changeset,
      action: dp(conn, "/orders/#{order.id}/payments"),
      paid_to_account_options: Accounting.cash_or_payable_account_options(),
      partner_options: Partners.partner_select_options(),
      liability_account_options: Accounting.liability_account_options()
    )
  end

  def create_payment(conn, %{"id" => id, "order_payment" => params}) do
    order = Orders.get_order!(id)

    # Log incoming params for debugging
    Logger.info("Creating payment for order #{order.id}")
    Logger.debug("Payment params received: #{inspect(params)}")

    # Parse payment_date string to Date for validation
    {_payment_date, date_parse_error} =
      case Date.from_iso8601(params["payment_date"]) do
        {:ok, date} -> {date, nil}
        {:error, reason} -> {nil, reason}
      end

    if date_parse_error do
      Logger.error("Invalid payment_date format: #{params["payment_date"]}, error: #{inspect(date_parse_error)}")
      changeset =
        Orders.change_order_payment(%OrderPayment{order_id: order.id})
        |> Ecto.Changeset.add_error(:payment_date, "Invalid date format")

      changeset = Map.put(changeset, :action, :insert)

      render(conn, :new_payment,
        order: order,
        payment_summary: Orders.payment_summary(order),
        changeset: changeset,
        action: dp(conn, "/orders/#{order.id}/payments"),
        paid_to_account_options: Accounting.cash_or_payable_account_options(),
        partner_options: Partners.partner_select_options(),
        liability_account_options: Accounting.liability_account_options()
      )
    else
      # Convert amounts from pesos to cents
      amount_cents = if params["amount"] && params["amount"] != "", do: MoneyHelper.pesos_to_cents(params["amount"]), else: nil

      # Only set split payment fields if they're actually provided (not empty strings)
      customer_amount_cents =
        if params["customer_amount"] && params["customer_amount"] != "" do
          MoneyHelper.pesos_to_cents(params["customer_amount"])
        else
          nil
        end

      partner_amount_cents =
        if params["partner_amount"] && params["partner_amount"] != "" do
          MoneyHelper.pesos_to_cents(params["partner_amount"])
        else
          nil
        end

      Logger.debug("Converted amounts - total: #{amount_cents}, customer: #{inspect(customer_amount_cents)}, partner: #{inspect(partner_amount_cents)}")

      # Make sure we tie the payment to the correct order_id explicitly
      # is_deposit is true if the order has NOT been delivered yet
      # (unearned revenue goes to Customer Deposits account 2200)
      # Once delivered, payments reduce AR (account 1100)
      is_deposit = order.status != "delivered"

      attrs =
        params
        |> Map.put("order_id", order.id)
        |> Map.put("is_deposit", is_deposit)
        |> Map.put("amount_cents", amount_cents)
        |> Map.put("customer_amount_cents", customer_amount_cents)
        |> Map.put("partner_amount_cents", partner_amount_cents)
        |> Map.drop(["customer_amount", "partner_amount", "amount"])

      Logger.debug("Final attrs for payment creation: #{inspect(attrs)}")

      # Capture outstanding balance BEFORE saving, so we can detect overpayment in the success branch
      outstanding_before_cents = Orders.payment_summary(order).outstanding_cents

      case Orders.create_order_payment(attrs) do
        {:ok, payment} ->
          Logger.info("Payment created successfully: payment_id=#{payment.id}, order_id=#{order.id}")

          # Handle overpayment: create AP entry if user chose "record"
          if params["owed_change_choice"] == "record" && amount_cents != nil do
            owed_change_cents = max(0, amount_cents - outstanding_before_cents)

            if owed_change_cents > 0 do
              payment_date =
                case Date.from_iso8601(params["payment_date"]) do
                  {:ok, d} -> d
                  _ -> Date.utc_today()
                end

              case OrderAccounting.record_owed_change_ap(order, owed_change_cents, payment_date, is_deposit) do
                {:ok, _} ->
                  Logger.info("Owed change AP entry recorded: #{owed_change_cents} cents for order #{order.id}")
                {:error, reason} ->
                  Logger.error("Failed to record owed change AP for order #{order.id}: #{inspect(reason)}")
              end
            end
          end

          conn
          |> put_flash(:info, "Payment recorded successfully.")
          |> redirect(to: dp(conn, "/orders/#{order.id}"))

        {:error, %Ecto.Changeset{} = changeset} ->
          # Log errors for debugging
          Logger.error("Payment creation failed for order #{order.id}")
          Logger.error("Changeset errors: #{inspect(changeset.errors)}")
          Logger.error("Changeset changes: #{inspect(changeset.changes)}")
          Logger.error("Params received: #{inspect(params)}")
          Logger.error("Processed attrs: #{inspect(attrs)}")

          # Mark changeset as having an attempted action so errors show in UI
          changeset = Map.put(changeset, :action, :insert)

          render(conn, :new_payment,
            order: order,
            payment_summary: Orders.payment_summary(order),
            changeset: changeset,
            action: dp(conn, "/orders/#{order.id}/payments"),
            paid_to_account_options: Accounting.cash_or_payable_account_options(),
            partner_options: Partners.partner_select_options(),
            liability_account_options: Accounting.liability_account_options()
          )
      end
    end
  end

  def stripe_link(conn, %{"id" => id}) do
    order = Orders.get_order!(id)

    base_url = "#{conn.scheme}://#{conn.host}#{if conn.port not in [80, 443], do: ":#{conn.port}", else: ""}"

    line_items = [
      %{
        price_data: %{
          currency: "mxn",
          unit_amount: order.variant.price_cents,
          product_data: %{
            name: "#{order.variant.product.name} — #{order.variant.name}"
          }
        },
        quantity: order.quantity || 1
      }
    ]

    case Stripe.Checkout.Session.create(%{
           mode: "payment",
           currency: "mxn",
           line_items: line_items,
           metadata: %{order_ids: to_string(order.id)},
           success_url: "#{base_url}/mr-munch-me/checkout/success?session_id={CHECKOUT_SESSION_ID}",
           cancel_url: "#{base_url}/mr-munch-me/checkout/cancel"
         }) do
      {:ok, session} ->
        Logger.info("Stripe link generated for order #{id}: session #{session.id}")
        Orders.set_stripe_checkout_session(order.id, session.id)
        render(conn, :stripe_link, order: order, stripe_url: session.url)

      {:error, reason} ->
        Logger.error("Failed to generate Stripe link for order #{id}: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Could not generate payment link. Please try again.")
        |> redirect(to: dp(conn, "/orders/#{id}"))
    end
  end

  def shipping_link(conn, %{"id" => id}) do
    order = Orders.get_order!(id)
    summary = Orders.payment_summary(order)
    render(conn, :shipping_link, order: order, suggested_amount: div(summary.shipping_cents, 100), stripe_url: nil)
  end

  def create_shipping_link(conn, %{"id" => id, "amount" => amount_str}) do
    order = Orders.get_order!(id)
    amount_cents = MoneyHelper.pesos_to_cents(amount_str)
    base_url = "#{conn.scheme}://#{conn.host}#{if conn.port not in [80, 443], do: ":#{conn.port}", else: ""}"

    case Stripe.Checkout.Session.create(%{
           mode: "payment",
           currency: "mxn",
           line_items: [
             %{
               price_data: %{
                 currency: "mxn",
                 unit_amount: amount_cents,
                 product_data: %{name: "Envío a domicilio — Pedido ##{order.id}"}
               },
               quantity: 1
             }
           ],
           metadata: %{shipping_order_id: to_string(order.id)},
           success_url: "#{base_url}/mr-munch-me/checkout/success?session_id={CHECKOUT_SESSION_ID}",
           cancel_url: "#{base_url}/mr-munch-me/checkout/cancel"
         }) do
      {:ok, session} ->
        Logger.info("Shipping link generated for order #{id}: session #{session.id}")
        render(conn, :shipping_link, order: order, stripe_url: session.url, amount_cents: amount_cents, suggested_amount: nil)

      {:error, reason} ->
        Logger.error("Failed to generate shipping link for order #{id}: #{inspect(reason)}")

        conn
        |> put_flash(:error, "No se pudo generar el link. Intenta de nuevo.")
        |> redirect(to: dp(conn, "/orders/#{id}"))
    end
  end

  def calendar(conn, params) do
    # Parse year and month from params, default to current month
    today = Date.utc_today()
    year = case params["year"] do
      nil -> today.year
      year_str -> String.to_integer(year_str)
    end

    month = case params["month"] do
      nil -> today.month
      month_str -> String.to_integer(month_str)
    end

    # Ensure valid month range
    month = cond do
      month < 1 -> 1
      month > 12 -> 12
      true -> month
    end

    # Get orders grouped by delivery date for this month
    orders_by_date = Orders.list_orders_for_calendar_month(year, month)

    # Calculate first day of month and last day
    first_day = Date.new!(year, month, 1)
    last_day = Date.end_of_month(first_day)

    # Calculate first day of calendar grid (might be from previous month)
    # Date.day_of_week returns 1=Monday, 7=Sunday, but we want Sunday=0
    weekday = Date.day_of_week(first_day)
    # Convert: 7 (Sunday) -> 0, 1 (Monday) -> 1, etc.
    days_from_sunday = if weekday == 7, do: 0, else: weekday
    calendar_start = Date.add(first_day, -days_from_sunday)

    # Calculate last day of calendar grid (complete 6 weeks = 42 days)
    calendar_end = Date.add(calendar_start, 41)

    render(conn, :calendar,
      year: year,
      month: month,
      first_day: first_day,
      last_day: last_day,
      calendar_start: calendar_start,
      calendar_end: calendar_end,
      orders_by_date: orders_by_date,
      today: today
    )
  end

  defp variant_price_map do
    Orders.list_active_variants()
    |> Map.new(fn v -> {v.id, v.price_cents || 0} end)
  end

  # Convert a "shipping_fee" pesos param to shipping_fee_cents before passing to domain.
  defp parse_shipping_fee(params) do
    case Map.pop(params, "shipping_fee") do
      {val, rest} when val not in [nil, ""] ->
        case Float.parse(to_string(val)) do
          {pesos, _} ->
            cents = round(pesos * 100)
            rest
            |> Map.put("shipping_fee_cents", cents)
            |> derive_customer_paid_shipping(cents)
          :error -> rest
        end

      {_, rest} ->
        rest
    end
  end

  # If customer_paid_shipping is not explicitly provided (e.g. from the shipping card,
  # not the full edit form), derive it from whether a shipping fee is set.
  defp derive_customer_paid_shipping(params, shipping_fee_cents) do
    if Map.has_key?(params, "customer_paid_shipping") do
      params
    else
      Map.put(params, "customer_paid_shipping", shipping_fee_cents > 0)
    end
  end

  # Format cents as a pesos string for form default values (e.g. 5000 -> "50.00")
  defp format_pesos(nil), do: "0.00"
  defp format_pesos(cents), do: :erlang.float_to_binary(cents / 100, decimals: 2)
end


defmodule LedgrWeb.Domains.MrMunchMe.OrderHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents

  embed_templates "order_html/*"

  def prev_month(year, month) do
    if month == 1 do
      %{year: year - 1, month: 12}
    else
      %{year: year, month: month - 1}
    end
  end

  def next_month(year, month) do
    if month == 12 do
      %{year: year + 1, month: 1}
    else
      %{year: year, month: month + 1}
    end
  end
end
