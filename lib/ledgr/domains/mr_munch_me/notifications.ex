defmodule Ledgr.Domains.MrMunchMe.Notifications do
  @moduledoc """
  MrMunchMe-specific outbound notifications.

  Currently sends WhatsApp alerts to the MrMunchMe business number when
  a new web order is created or when an existing COD order is paid via
  Stripe. All sends are fire-and-forget (`CallMeBot.send_text_async/2`)
  so customer-facing flows never block on the WhatsApp API.

  ## Configuration

      config :ledgr, :mr_munch_me,
        alert_phone: System.get_env("MR_MUNCH_ME_ALERT_PHONE") || "525543417149"

  Defaults to the public MrMunchMe business number.
  """

  require Logger

  alias Ledgr.Notifications.CallMeBot

  @default_phone "525543417149"

  @doc """
  Fire-and-forget alert when a new order (or set of orders from one
  checkout) is created via the storefront.
  """
  def notify_new_order(orders, payment_method) when is_list(orders) do
    case orders do
      [] ->
        :ok

      [first | _] = orders ->
        message = build_new_order_message(orders, first, payment_method)
        CallMeBot.send_text_async(alert_phone(), message)
    end
  end

  @doc """
  Fire-and-forget alert when an existing COD order is paid via Stripe.
  `orders` is the list of orders that just received a Stripe payment.
  """
  def notify_payment_received(orders) when is_list(orders) do
    case orders do
      [] ->
        :ok

      [first | _] = orders ->
        message = build_payment_message(orders, first)
        CallMeBot.send_text_async(alert_phone(), message)
    end
  end

  # ─── Message builders ────────────────────────────────────────────────

  defp build_new_order_message(orders, first, payment_method) do
    order_ids =
      orders
      |> Enum.map(&"##{&1.id}")
      |> Enum.join(", ")

    items_block =
      orders
      |> Enum.map(fn o ->
        qty = o.quantity || 1
        "• #{qty}x #{order_variant_name(o)}"
      end)
      |> Enum.join("\n")

    total_cents =
      Enum.reduce(orders, 0, fn o, acc ->
        acc + order_variant_price(o) * (o.quantity || 1)
      end)

    payment_label =
      case payment_method do
        "stripe" -> "Pagado por Stripe"
        "cod" -> "Pago contra entrega"
        other -> to_string(other)
      end

    delivery_label =
      case first.delivery_type do
        "delivery" -> "Entrega a domicilio"
        "pickup" -> "Recoge en local"
        other -> to_string(other)
      end

    """
    🍪 *Nuevo pedido MrMunchMe* (#{order_ids})

    👤 #{first.customer_name || "Cliente"}
    📞 #{first.customer_phone || "—"}

    #{items_block}

    💵 Total: $#{format_pesos(total_cents)} MXN
    💳 #{payment_label}
    🚚 #{delivery_label} — #{format_date(first.delivery_date)}#{address_line(first)}#{notes_line(first)}
    """
    |> String.trim()
  end

  defp build_payment_message(orders, first) do
    order_ids =
      orders
      |> Enum.map(&"##{&1.id}")
      |> Enum.join(", ")

    """
    💳 *Pago Stripe recibido* (#{order_ids})

    👤 #{first.customer_name || "Cliente"}
    """
    |> String.trim()
  end

  # ─── Field helpers (defensive against missing preloads) ───────────────

  defp order_variant_name(order) do
    case order do
      %{variant: %{name: variant_name, product: %{name: product_name}}}
      when is_binary(product_name) ->
        "#{product_name} – #{variant_name}"

      %{variant: %{name: variant_name}} when is_binary(variant_name) ->
        variant_name

      _ ->
        "Producto"
    end
  end

  defp order_variant_price(%{variant: %{price_cents: cents}}) when is_integer(cents), do: cents
  defp order_variant_price(_), do: 0

  defp address_line(%{delivery_address: addr}) when is_binary(addr) and addr != "",
    do: "\n📍 #{addr}"

  defp address_line(_), do: ""

  defp notes_line(%{special_instructions: notes}) when is_binary(notes) and notes != "",
    do: "\n📝 #{notes}"

  defp notes_line(_), do: ""

  defp format_pesos(cents) when is_integer(cents) do
    (cents / 100)
    |> :erlang.float_to_binary(decimals: 2)
  end

  defp format_pesos(_), do: "0.00"

  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%d %b %Y")
  defp format_date(_), do: "—"

  defp alert_phone do
    Application.get_env(:ledgr, :mr_munch_me, [])
    |> Keyword.get(:alert_phone, @default_phone)
  end
end
