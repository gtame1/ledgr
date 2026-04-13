defmodule LedgrWeb.HelloDoctorStripeWebhookController do
  use LedgrWeb, :controller

  require Logger

  alias Ledgr.Domains.HelloDoctor.StripeSync

  @doc """
  Handles Stripe webhook events for HelloDoctor's separate Stripe account.

  The bot sends Stripe payment links to patients. When payment completes,
  Stripe fires checkout.session.completed. We always record the payment
  (via StripeSync.upsert_payment/1), and if metadata contains conversation_id
  or consultation_id, we also link it to the consultation.
  """
  def handle(conn, _params) do
    raw_body = conn.assigns[:raw_body] || ""
    sig_header = get_req_header(conn, "stripe-signature") |> List.first()
    webhook_secret = Application.get_env(:ledgr, :hello_doctor_stripe_webhook_secret)

    # Set HelloDoctor as active domain/repo (webhooks have no session)
    Ledgr.Domain.put_current(Ledgr.Domains.HelloDoctor)
    Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)

    case Stripe.Webhook.construct_event(raw_body, sig_header, webhook_secret) do
      {:ok, %Stripe.Event{type: "checkout.session.completed", data: %{object: session}}} ->
        handle_checkout_completed(conn, session)

      {:ok, %Stripe.Event{type: "charge.refunded", data: %{object: charge}}} ->
        handle_refund(conn, charge)

      {:ok, %Stripe.Event{type: type}} ->
        Logger.debug("[HelloDoctor] Stripe webhook: unhandled event type #{type}")
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.warning("[HelloDoctor] Stripe webhook signature verification failed: #{inspect(reason)}")
        send_resp(conn, 400, "bad request")
    end
  end

  defp handle_checkout_completed(conn, session) do
    amount_pesos = (session.amount_total || 0) / 100.0
    metadata = session.metadata || %{}

    Logger.info("[HelloDoctor] Stripe checkout completed: session=#{session.id}, amount=$#{amount_pesos}, metadata=#{inspect(metadata)}")

    case StripeSync.upsert_payment(session) do
      {:ok, :already_exists} ->
        Logger.info("[HelloDoctor] Stripe webhook: payment for session #{session.id} already recorded, skipping")
        send_resp(conn, 200, "ok — already recorded")

      {:ok, payment} ->
        link_info = if payment.consultation_id, do: " (linked to consultation #{payment.consultation_id})", else: " (unlinked — no metadata)"
        Logger.info("[HelloDoctor] Stripe webhook: recorded payment for session #{session.id}, amount: $#{amount_pesos}#{link_info}")
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.error("[HelloDoctor] Stripe webhook: failed to record payment for session #{session.id}: #{inspect(reason)}")
        send_resp(conn, 500, "error")
    end
  end

  defp handle_refund(conn, charge) do
    Logger.info("[HelloDoctor] Stripe webhook: charge.refunded received for charge #{charge.id}")
    send_resp(conn, 200, "ok")
  end
end
