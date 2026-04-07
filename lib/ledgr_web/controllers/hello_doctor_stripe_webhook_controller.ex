defmodule LedgrWeb.HelloDoctorStripeWebhookController do
  use LedgrWeb, :controller

  require Logger

  alias Ledgr.Domains.HelloDoctor.Consultations

  @doc """
  Handles Stripe webhook events for HelloDoctor's separate Stripe account.

  The bot sends Stripe payment links to patients. When payment completes,
  Stripe fires checkout.session.completed with consultation_id in metadata.
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
    consultation_id = get_in(session.metadata, ["consultation_id"])

    amount_pesos = (session.amount_total || 0) / 100.0
    customer_email = session.customer_details && session.customer_details.email
    customer_name = session.customer_details && session.customer_details.name

    Logger.info("[HelloDoctor] Stripe checkout completed: session=#{session.id}, amount=$#{amount_pesos}, email=#{customer_email || "none"}, name=#{customer_name || "none"}, metadata=#{inspect(session.metadata)}")

    if is_nil(consultation_id) do
      Logger.warning("[HelloDoctor] Stripe webhook: no consultation_id in metadata — payment received but cannot link to consultation. Session: #{session.id}, amount: $#{amount_pesos}")
      send_resp(conn, 200, "ok — payment received, no consultation_id to link")
    else
      case Consultations.get_consultation(consultation_id) do
        nil ->
          Logger.warning("[HelloDoctor] Stripe webhook: consultation #{consultation_id} not found")
          send_resp(conn, 200, "ok — consultation not found")

        consultation ->
          if consultation.payment_status in ["paid", "confirmed"] do
            Logger.info("[HelloDoctor] Stripe webhook: consultation #{consultation_id} already paid, skipping")
            send_resp(conn, 200, "ok — already paid")
          else
            case Consultations.record_stripe_payment(consultation, %{
                   payment_amount: amount_pesos,
                   stripe_session_id: session.id
                 }) do
              {:ok, _consultation} ->
                Logger.info("[HelloDoctor] Stripe webhook: recorded payment for consultation #{consultation_id}, amount: $#{amount_pesos}")
                send_resp(conn, 200, "ok")

              {:error, reason} ->
                Logger.error("[HelloDoctor] Stripe webhook: failed to record payment for consultation #{consultation_id}: #{inspect(reason)}")
                send_resp(conn, 500, "error")
            end
          end
      end
    end
  end

  defp handle_refund(conn, charge) do
    # Future: handle refunds by looking up consultation via charge metadata
    Logger.info("[HelloDoctor] Stripe webhook: charge.refunded received for charge #{charge.id}")
    send_resp(conn, 200, "ok")
  end
end
