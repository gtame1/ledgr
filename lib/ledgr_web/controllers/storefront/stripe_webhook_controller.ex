defmodule LedgrWeb.Storefront.StripeWebhookController do
  use LedgrWeb, :controller

  require Logger

  alias Ledgr.Domains.MrMunchMe.{Orders, PendingCheckouts}

  def handle(conn, _params) do
    raw_body = conn.assigns[:raw_body] || ""
    sig_header = get_req_header(conn, "stripe-signature") |> List.first()
    webhook_secret = Application.get_env(:ledgr, :stripe_webhook_secret)

    case Stripe.Webhook.construct_event(raw_body, sig_header, webhook_secret) do
      {:ok, %Stripe.Event{type: "checkout.session.completed", data: %{object: session}}} ->
        handle_checkout_completed(conn, session)

      {:ok, %Stripe.Event{type: type}} ->
        Logger.debug("Stripe webhook: unhandled event type #{type}")
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.warning("Stripe webhook signature verification failed: #{inspect(reason)}")
        send_resp(conn, 400, "bad request")
    end
  end

  defp handle_checkout_completed(conn, session) do
    order_ids_str = get_in(session.metadata, ["order_ids"])
    pending_checkout_id = get_in(session.metadata, ["pending_checkout_id"])
    shipping_order_id_str = get_in(session.metadata, ["shipping_order_id"])

    cond do
      shipping_order_id_str ->
        order_id = String.to_integer(shipping_order_id_str)

        case Orders.create_shipping_payment(order_id, session.amount_total) do
          {:ok, _} ->
            Logger.info("Stripe webhook: recorded shipping payment for order #{order_id}")
            send_resp(conn, 200, "ok")

          {:error, reason} ->
            Logger.error("Stripe webhook: failed to record shipping payment for order #{order_id}: #{inspect(reason)}")
            send_resp(conn, 500, "error")
        end

      order_ids_str ->
        # COD → Stripe conversion path: create payments for existing orders
        order_ids = order_ids_str |> String.split(",") |> Enum.map(&String.to_integer/1)

        case Orders.create_payments_for_existing_orders(order_ids, session.id) do
          {:ok, _} ->
            Logger.info("Stripe webhook: recorded Stripe payments for existing orders #{order_ids_str}")
            send_resp(conn, 200, "ok")

          {:error, reason} ->
            Logger.error("Stripe webhook: failed to record payments for orders #{order_ids_str}: #{inspect(reason)}")
            send_resp(conn, 500, "error")
        end

      pending_checkout_id ->
        pending = PendingCheckouts.get_by_id(pending_checkout_id)

        cond do
          is_nil(pending) ->
            Logger.warning("Stripe webhook: PendingCheckout #{pending_checkout_id} not found")
            send_resp(conn, 200, "ok")

          PendingCheckouts.already_processed?(pending) ->
            Logger.info("Stripe webhook: PendingCheckout #{pending_checkout_id} already processed, skipping")
            send_resp(conn, 200, "ok")

          true ->
            case Orders.create_orders_from_pending_checkout(pending, session.id) do
              {:ok, _orders} ->
                {:ok, _} = PendingCheckouts.mark_processed(pending)
                Logger.info("Stripe webhook: created orders for session #{session.id}")
                send_resp(conn, 200, "ok")

              {:error, reason} ->
                Logger.error("Stripe webhook: failed to create orders for session #{session.id}: #{inspect(reason)}")
                send_resp(conn, 500, "error")
            end
        end

      true ->
        Logger.warning("Stripe webhook: checkout.session.completed missing known metadata for session #{session.id}")
        send_resp(conn, 200, "ok")
    end
  end
end
