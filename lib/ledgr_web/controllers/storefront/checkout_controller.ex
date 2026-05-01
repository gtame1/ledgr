defmodule LedgrWeb.Storefront.CheckoutController do
  use LedgrWeb, :controller

  require Logger

  alias Ledgr.Domains.MrMunchMe.{Orders, PendingCheckouts}
  alias Ledgr.Core.Customers

  @whatsapp_number "525543417149"

  def new(conn, _params) do
    cart = get_session(conn, :cart) || %{}

    if map_size(cart) == 0 do
      conn
      |> put_flash(:error, "Tu carrito está vacío.")
      |> redirect(to: "/mr-munch-me/menu")
    else
      {cart_items, cart_total} = load_cart_items(cart)

      conn
      |> assign(:storefront, true)
      |> assign(:page_title, "Checkout")
      |> render(:new,
        cart_items: cart_items,
        cart_total: cart_total,
        errors: %{},
        form_values: %{},
        discount: nil,
        min_delivery_date: min_delivery_date()
      )
    end
  end

  def validate_discount(conn, %{"code" => code}) do
    case Orders.validate_discount_code(code) do
      {:ok, dc} ->
        json(conn, %{
          valid: true,
          discount_type: dc.discount_type,
          discount_value: Decimal.to_string(dc.discount_value),
          label: discount_label(dc)
        })

      {:error, reason} ->
        json(conn, %{valid: false, error: reason})
    end
  end

  def validate_discount(conn, _params) do
    json(conn, %{valid: false, error: "Código requerido"})
  end

  def create(conn, %{"checkout" => checkout_params}) do
    cart = get_session(conn, :cart) || %{}

    if map_size(cart) == 0 do
      conn
      |> put_flash(:error, "Tu carrito está vacío.")
      |> redirect(to: "/mr-munch-me/menu")
    else
      {cart_items, cart_total} = load_cart_items(cart)

      customer_phone = String.trim(checkout_params["customer_phone"] || "")
      customer_name = String.trim(checkout_params["customer_name"] || "")
      customer_email = String.trim(checkout_params["customer_email"] || "")

      # Validate discount code if provided
      discount_code_str = String.trim(checkout_params["discount_code"] || "")

      {discount_result, discount_struct} =
        if discount_code_str != "" do
          case Orders.validate_discount_code(discount_code_str) do
            {:ok, dc} -> {:ok, dc}
            {:error, _} -> {:error, nil}
          end
        else
          {:skip, nil}
        end

      errors =
        %{}
        |> maybe_add_error(customer_name == "", :customer_name, "El nombre es requerido")
        |> maybe_add_error(customer_phone == "", :customer_phone, "El teléfono es requerido")
        |> maybe_add_error(
          String.trim(checkout_params["delivery_type"] || "") == "",
          :delivery_type,
          "Por favor selecciona recoger o envío a domicilio"
        )
        |> maybe_add_error(
          String.trim(checkout_params["delivery_date"] || "") == "",
          :delivery_date,
          "Por favor selecciona una fecha"
        )
        |> maybe_add_error(
          date_too_soon?(checkout_params["delivery_date"]),
          :delivery_date,
          "La fecha más próxima disponible es #{Date.to_string(min_delivery_date())} (mínimo 36 horas de anticipación)"
        )
        |> maybe_add_error(
          String.trim(checkout_params["delivery_time"] || "") == "",
          :delivery_time,
          "Por favor indica una hora preferida"
        )
        |> maybe_add_error(
          String.trim(checkout_params["payment_method"] || "") == "",
          :payment_method,
          "Por favor selecciona un método de pago"
        )
        |> maybe_add_error(
          discount_code_str != "" && discount_result == :error,
          :discount_code,
          "Código de descuento inválido o expirado"
        )

      if map_size(errors) > 0 do
        conn
        |> assign(:storefront, true)
        |> assign(:page_title, "Checkout")
        |> put_flash(:error, "Por favor corrige los errores a continuación.")
        |> render(:new,
          cart_items: cart_items,
          cart_total: cart_total,
          errors: errors,
          form_values: checkout_params,
          discount: discount_struct,
          min_delivery_date: min_delivery_date()
        )
      else
        customer_attrs = %{
          name: customer_name,
          email: if(customer_email != "", do: customer_email, else: nil),
          delivery_address: checkout_params["delivery_address"]
        }

        case Customers.find_or_create_by_phone(customer_phone, customer_attrs) do
          {:ok, customer} ->
            case checkout_params["payment_method"] do
              "stripe" ->
                redirect_to_stripe(
                  conn,
                  cart,
                  cart_items,
                  customer,
                  checkout_params,
                  discount_struct
                )

              "cod" ->
                create_cod_orders(
                  conn,
                  cart,
                  cart_items,
                  customer,
                  checkout_params,
                  discount_struct
                )
            end

          {:error, _} ->
            conn
            |> assign(:storefront, true)
            |> assign(:page_title, "Checkout")
            |> put_flash(:error, "Hubo un problema con tu información. Intenta de nuevo.")
            |> render(:new,
              cart_items: cart_items,
              cart_total: cart_total,
              errors: %{customer_phone: "Número de teléfono inválido"},
              form_values: checkout_params,
              discount: discount_struct,
              min_delivery_date: min_delivery_date()
            )
        end
      end
    end
  end

  def success(conn, %{"session_id" => stripe_session_id}) do
    orders = Orders.get_orders_by_stripe_session(stripe_session_id)

    orders =
      if Enum.empty?(orders) do
        case attempt_order_creation_fallback(stripe_session_id) do
          :ok -> Orders.get_orders_by_stripe_session(stripe_session_id)
          :skip -> []
        end
      else
        orders
      end

    if Enum.empty?(orders) do
      conn
      |> assign(:storefront, true)
      |> assign(:page_title, "Procesando tu pedido...")
      |> render(:processing, stripe_session_id: stripe_session_id)
    else
      first_order = hd(orders)
      customer_name = first_order.customer_name
      delivery_type = first_order.delivery_type
      delivery_date = first_order.delivery_date
      special_instructions = Enum.find_value(orders, fn o -> o.special_instructions end)

      items =
        Enum.map(orders, fn o ->
          %{
            product_name: o.variant.product.name,
            variant_name: o.variant.name,
            quantity: o.quantity || 1,
            subtotal_cents: o.variant.price_cents * (o.quantity || 1)
          }
        end)

      order_ids = Enum.map(orders, & &1.id)

      whatsapp_url =
        build_whatsapp_url(
          customer_name,
          order_ids,
          items,
          delivery_type,
          delivery_date,
          "stripe",
          special_instructions
        )

      conn
      |> delete_session(:cart)
      |> assign(:storefront, true)
      |> assign(:page_title, "¡Pedido confirmado!")
      |> render(:success,
        orders: orders,
        customer_name: customer_name,
        delivery_type: delivery_type,
        delivery_date: delivery_date,
        whatsapp_url: whatsapp_url
      )
    end
  end

  def success(conn, _params) do
    redirect(conn, to: "/mr-munch-me/menu")
  end

  def pay_existing_with_stripe(conn, %{"order_ids" => order_id_strings}) do
    order_ids =
      order_id_strings
      |> List.wrap()
      |> Enum.map(&String.to_integer/1)

    orders = Enum.map(order_ids, &Orders.get_order!(&1))

    line_items =
      Enum.map(orders, fn order ->
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
      end)

    order_ids_str = Enum.join(order_ids, ",")

    base_url =
      "#{conn.scheme}://#{conn.host}#{if conn.port not in [80, 443], do: ":#{conn.port}", else: ""}"

    case Stripe.Checkout.Session.create(%{
           mode: "payment",
           currency: "mxn",
           line_items: line_items,
           metadata: %{order_ids: order_ids_str},
           success_url:
             "#{base_url}/mr-munch-me/checkout/success?session_id={CHECKOUT_SESSION_ID}",
           cancel_url: "#{base_url}/mr-munch-me/checkout/cancel"
         }) do
      {:ok, session} ->
        redirect(conn, external: session.url)

      {:error, reason} ->
        Logger.error(
          "Stripe session creation failed for existing orders #{order_ids_str}: #{inspect(reason)}"
        )

        conn
        |> put_flash(:error, "No se pudo iniciar el pago. Por favor intenta de nuevo.")
        |> redirect(to: "/mr-munch-me/menu")
    end
  end

  def pay_existing_with_stripe(conn, _params) do
    conn
    |> put_flash(:error, "No se encontraron pedidos para pagar.")
    |> redirect(to: "/mr-munch-me/menu")
  end

  def cancel(conn, _params) do
    conn
    |> put_flash(:info, "El pago fue cancelado. Tu carrito sigue guardado.")
    |> redirect(to: "/mr-munch-me/cart")
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp attempt_order_creation_fallback(stripe_session_id) do
    with {:ok, session} <- Stripe.Checkout.Session.retrieve(stripe_session_id),
         "paid" <- session.payment_status do
      order_ids_str = session.metadata["order_ids"]

      if order_ids_str do
        # COD → Stripe conversion path: create payments for existing orders
        order_ids = order_ids_str |> String.split(",") |> Enum.map(&String.to_integer/1)

        case Orders.create_payments_for_existing_orders(order_ids, stripe_session_id) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error("Stripe payment for existing COD orders failed: #{inspect(reason)}")
            :skip
        end
      else
        # Normal PendingCheckout path
        pending = PendingCheckouts.get_by_stripe_session(stripe_session_id)

        if pending && !PendingCheckouts.already_processed?(pending) do
          case Orders.create_orders_from_pending_checkout(
                 pending,
                 stripe_session_id,
                 session.amount_total
               ) do
            {:ok, _} ->
              PendingCheckouts.mark_processed(pending)
              :ok

            {:error, reason} ->
              Logger.error("Success page fallback order creation failed: #{inspect(reason)}")
              :skip
          end
        else
          :skip
        end
      end
    else
      _ -> :skip
    end
  end

  defp redirect_to_stripe(conn, cart, cart_items, customer, checkout_params, discount_struct) do
    checkout_attrs = %{
      "delivery_type" => checkout_params["delivery_type"],
      "delivery_date" => checkout_params["delivery_date"],
      "delivery_time" => checkout_params["delivery_time"],
      "delivery_address" => checkout_params["delivery_address"],
      "special_instructions" => checkout_params["special_instructions"],
      "discount_type" => discount_struct && discount_struct.discount_type,
      "discount_value" => discount_struct && Decimal.to_string(discount_struct.discount_value)
    }

    with {:ok, pending} <- PendingCheckouts.create(cart, customer.id, checkout_attrs),
         line_items = build_stripe_line_items(cart_items, discount_struct),
         {:ok, session} <- create_stripe_session(pending.id, line_items, conn),
         {:ok, _} <- PendingCheckouts.set_stripe_session(pending, session.id) do
      if discount_struct, do: Orders.increment_discount_code_uses(discount_struct)
      redirect(conn, external: session.url)
    else
      {:error, reason} ->
        Logger.error("Stripe session creation failed: #{inspect(reason)}")

        {cart_items, cart_total} = load_cart_items(cart)

        conn
        |> assign(:storefront, true)
        |> assign(:page_title, "Checkout")
        |> put_flash(:error, "No se pudo iniciar el pago. Por favor intenta de nuevo.")
        |> render(:new,
          cart_items: cart_items,
          cart_total: cart_total,
          errors: %{},
          form_values: checkout_params,
          discount: discount_struct,
          min_delivery_date: min_delivery_date()
        )
    end
  end

  defp create_cod_orders(conn, cart, cart_items, customer, checkout_params, discount_struct) do
    checkout_attrs = %{
      "delivery_type" => checkout_params["delivery_type"],
      "delivery_date" => checkout_params["delivery_date"],
      "delivery_time" => checkout_params["delivery_time"],
      "delivery_address" => checkout_params["delivery_address"],
      "special_instructions" => checkout_params["special_instructions"],
      "discount_type" => discount_struct && discount_struct.discount_type,
      "discount_value" => discount_struct && Decimal.to_string(discount_struct.discount_value)
    }

    if discount_struct, do: Orders.increment_discount_code_uses(discount_struct)

    case Orders.create_orders_cod(cart, customer.id, checkout_attrs) do
      {:ok, orders} ->
        delivery_type = checkout_params["delivery_type"]

        delivery_date =
          case Date.from_iso8601(checkout_params["delivery_date"] || "") do
            {:ok, d} -> d
            _ -> nil
          end

        cart_total = Enum.reduce(cart_items, 0, fn item, acc -> acc + item.subtotal end)
        special_instructions = checkout_params["special_instructions"]

        items =
          Enum.map(cart_items, fn item ->
            %{
              product_name: item.product.name,
              variant_name: item.variant.name,
              quantity: item.quantity,
              subtotal_cents: item.subtotal
            }
          end)

        order_ids = Enum.map(orders, & &1.id)

        whatsapp_url =
          build_whatsapp_url(
            customer.name,
            order_ids,
            items,
            delivery_type,
            delivery_date,
            "cod",
            special_instructions
          )

        conn
        |> delete_session(:cart)
        |> assign(:storefront, true)
        |> assign(:page_title, "¡Pedido registrado!")
        |> render(:confirmation,
          orders: orders,
          customer_name: customer.name,
          delivery_type: delivery_type,
          delivery_date: delivery_date,
          cart_items: cart_items,
          cart_total: cart_total,
          whatsapp_url: whatsapp_url
        )

      {:error, reason} ->
        Logger.error("COD order creation failed: #{inspect(reason)}")

        {cart_items_reload, cart_total} = load_cart_items(cart)

        conn
        |> assign(:storefront, true)
        |> assign(:page_title, "Checkout")
        |> put_flash(:error, "Hubo un error al crear tu pedido. Por favor intenta de nuevo.")
        |> render(:new,
          cart_items: cart_items_reload,
          cart_total: cart_total,
          errors: %{},
          form_values: checkout_params,
          discount: discount_struct,
          min_delivery_date: min_delivery_date()
        )
    end
  end

  defp build_stripe_line_items(cart_items, discount_struct) do
    product_items =
      Enum.map(cart_items, fn item ->
        %{
          price_data: %{
            currency: "mxn",
            unit_amount: item.variant.price_cents,
            product_data: %{name: "#{item.product.name} — #{item.variant.name}"}
          },
          quantity: item.quantity
        }
      end)

    if discount_struct do
      total_cents =
        Enum.reduce(cart_items, 0, fn i, acc -> acc + i.variant.price_cents * i.quantity end)

      discount_cents =
        case discount_struct.discount_type do
          "flat" ->
            round(Decimal.to_float(discount_struct.discount_value) * 100)

          "percentage" ->
            pct = Decimal.to_float(discount_struct.discount_value) / 100
            round(total_cents * pct)
        end

      discount_cents = min(discount_cents, total_cents)

      discount_item = %{
        price_data: %{
          currency: "mxn",
          unit_amount: -discount_cents,
          product_data: %{name: "Descuento (#{discount_label(discount_struct)})"}
        },
        quantity: 1
      }

      product_items ++ [discount_item]
    else
      product_items
    end
  end

  defp create_stripe_session(pending_checkout_id, line_items, conn) do
    base_url =
      "#{conn.scheme}://#{conn.host}#{if conn.port not in [80, 443], do: ":#{conn.port}", else: ""}"

    Stripe.Checkout.Session.create(%{
      mode: "payment",
      currency: "mxn",
      line_items: line_items,
      metadata: %{pending_checkout_id: pending_checkout_id},
      success_url: "#{base_url}/mr-munch-me/checkout/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{base_url}/mr-munch-me/checkout/cancel"
    })
  end

  defp build_whatsapp_url(
         customer_name,
         order_ids,
         items,
         delivery_type,
         delivery_date,
         payment_method,
         special_instructions
       ) do
    delivery_label =
      case delivery_type do
        "pickup" -> "Recoger en local"
        "delivery" -> "Envío a domicilio"
        _ -> delivery_type
      end

    date_str = if delivery_date, do: fmt_date(delivery_date, "%d/%m/%Y"), else: "—"

    {intro, payment_line} =
      if payment_method == "cod" do
        {"¡Hola! Acabo de hacer un pedido en MrMunchMe.",
         "Pago: Al recibir (efectivo / transferencia)"}
      else
        {"¡Hola! Acabo de pagar mi pedido en MrMunchMe.", "Pago: Realizado con tarjeta en línea"}
      end

    order_ids_str = order_ids |> Enum.map(&"##{&1}") |> Enum.join(", ")

    items_lines =
      items
      |> Enum.map(fn item ->
        price_pesos = div(item.subtotal_cents, 100)
        "• #{item.product_name} · #{item.variant_name} ×#{item.quantity} — $#{price_pesos}"
      end)
      |> Enum.join("\n")

    total_cents = Enum.reduce(items, 0, fn item, acc -> acc + item.subtotal_cents end)
    total_pesos = div(total_cents, 100)

    instructions_line =
      if special_instructions && String.trim(special_instructions) != "" do
        "\nInstrucciones especiales: #{String.trim(special_instructions)}"
      else
        ""
      end

    message = """
    #{intro}

    Nombre: #{customer_name}
    Pedido: #{order_ids_str}
    Tipo de entrega: #{delivery_label}
    Fecha: #{date_str}
    #{payment_line}

    Artículos:
    #{items_lines}
    Total: $#{total_pesos} MXN#{instructions_line}

    ¿Pueden confirmar los detalles de entrega?
    """

    "https://wa.me/#{@whatsapp_number}?text=#{URI.encode(String.trim(message))}"
  end

  defp maybe_add_error(errors, true, field, message), do: Map.put(errors, field, message)
  defp maybe_add_error(errors, false, _field, _message), do: errors

  defp mexico_city_now, do: DateTime.now!("America/Mexico_City")

  # Minimum delivery date: at least 36 hours from now
  defp min_delivery_date do
    mexico_city_now()
    |> DateTime.add(36 * 3600, :second)
    |> DateTime.to_date()
  end

  defp date_too_soon?(date_str) do
    case Date.from_iso8601(date_str || "") do
      {:ok, d} -> Date.before?(d, min_delivery_date())
      _ -> false
    end
  end

  defp discount_label(%{discount_type: "flat", discount_value: v}),
    do: "$#{Decimal.to_string(v)} MXN"

  defp discount_label(%{discount_type: "percentage", discount_value: v}),
    do: "#{Decimal.to_string(v)}%"

  defp discount_label(_), do: ""

  defp load_cart_items(cart) when map_size(cart) == 0, do: {[], 0}

  defp load_cart_items(cart) do
    items =
      Enum.reduce(cart, [], fn {variant_id_str, quantity}, acc ->
        case Integer.parse(to_string(variant_id_str)) do
          {id, _} ->
            try do
              variant = Orders.get_variant!(id)
              product = variant.product
              subtotal = variant.price_cents * quantity

              [
                %{product: product, variant: variant, quantity: quantity, subtotal: subtotal}
                | acc
              ]
            rescue
              Ecto.NoResultsError -> acc
            end

          :error ->
            acc
        end
      end)
      |> Enum.sort_by(fn item -> "#{item.product.name} #{item.variant.name}" end)

    total = Enum.reduce(items, 0, fn item, acc -> acc + item.subtotal end)
    {items, total}
  end
end
