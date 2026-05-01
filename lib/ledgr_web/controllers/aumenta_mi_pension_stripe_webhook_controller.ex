defmodule LedgrWeb.AumentaMiPensionStripeWebhookController do
  use LedgrWeb, :controller

  require Logger

  alias Ledgr.Domains.AumentaMiPension.StripeSync

  @doc """
  Handles Stripe webhook events for AumentaMiPensión's separate Stripe account.

  On `checkout.session.completed` we record the payment via `StripeSync.upsert_payment/1`
  and create a journal entry. On `charge.refunded` we mark the local payment
  as refunded.
  """
  def handle(conn, _params) do
    webhook_secret = Application.get_env(:ledgr, :aumenta_mi_pension_stripe_webhook_secret)

    if is_nil(webhook_secret) or webhook_secret == "" do
      Logger.debug(
        "[AumentaMiPension] Stripe webhook hit but no webhook secret configured; ignoring"
      )

      send_resp(conn, 200, "ok")
    else
      dispatch(conn, webhook_secret)
    end
  end

  defp dispatch(conn, webhook_secret) do
    raw_body = conn.assigns[:raw_body] || ""
    sig_header = get_req_header(conn, "stripe-signature") |> List.first()

    # Webhooks have no session — explicitly bind domain + repo for this request.
    Ledgr.Domain.put_current(Ledgr.Domains.AumentaMiPension)
    Ledgr.Repo.put_active_repo(Ledgr.Repos.AumentaMiPension)

    case Stripe.Webhook.construct_event(raw_body, sig_header, webhook_secret) do
      {:ok, %Stripe.Event{type: "checkout.session.completed", data: %{object: session}}} ->
        handle_checkout_completed(conn, session)

      {:ok, %Stripe.Event{type: "charge.refunded", data: %{object: charge}}} ->
        handle_refund(conn, charge)

      {:ok, %Stripe.Event{type: type}} ->
        Logger.debug("[AumentaMiPension] Stripe webhook: unhandled event type #{type}")
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.warning(
          "[AumentaMiPension] Stripe webhook signature verification failed: #{inspect(reason)}"
        )

        send_resp(conn, 400, "bad request")
    end
  end

  defp handle_checkout_completed(conn, session) do
    amount_pesos = (session.amount_total || 0) / 100.0
    metadata = session.metadata || %{}

    Logger.info(
      "[AumentaMiPension] Stripe checkout completed: session=#{session.id}, amount=$#{amount_pesos}, metadata=#{inspect(metadata)}"
    )

    case StripeSync.upsert_payment(session) do
      {:ok, :already_exists} ->
        Logger.info(
          "[AumentaMiPension] Stripe webhook: payment for session #{session.id} already recorded, skipping"
        )

        send_resp(conn, 200, "ok — already recorded")

      {:ok, payment} ->
        link_info =
          if payment.consultation_id,
            do: " (linked to consultation #{payment.consultation_id})",
            else: " (unlinked — no metadata)"

        Logger.info(
          "[AumentaMiPension] Stripe webhook: recorded payment for session #{session.id}, amount: $#{amount_pesos}#{link_info}"
        )

        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.error(
          "[AumentaMiPension] Stripe webhook: failed to record payment for session #{session.id}: #{inspect(reason)}"
        )

        send_resp(conn, 500, "error")
    end
  end

  defp handle_refund(conn, charge) do
    payment_intent_id =
      case charge.payment_intent do
        nil -> nil
        pi when is_binary(pi) -> pi
        %{id: id} -> id
      end

    if payment_intent_id do
      alias Ledgr.Domains.AumentaMiPension.StripePayments.StripePayment

      case Ledgr.Repo.get_by(StripePayment, stripe_payment_intent_id: payment_intent_id) do
        nil ->
          Logger.warning(
            "[AumentaMiPension] Stripe webhook: charge.refunded for unknown payment_intent #{payment_intent_id}"
          )

        payment ->
          payment
          |> StripePayment.changeset(%{status: "refunded"})
          |> Ledgr.Repo.update()

          Logger.info(
            "[AumentaMiPension] Stripe webhook: marked payment #{payment.id} as refunded (charge #{charge.id})"
          )
      end
    else
      Logger.warning(
        "[AumentaMiPension] Stripe webhook: charge.refunded with no payment_intent (charge #{charge.id})"
      )
    end

    send_resp(conn, 200, "ok")
  end
end
