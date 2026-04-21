defmodule LedgrWeb.AumentaMiPensionStripeWebhookController do
  use LedgrWeb, :controller

  require Logger

  def handle(conn, _params) do
    webhook_secret = Application.get_env(:ledgr, :aumenta_mi_pension_stripe_webhook_secret)

    if is_nil(webhook_secret) or webhook_secret == "" do
      Logger.debug("[AumentaMiPension] Stripe webhook hit but no webhook secret configured; ignoring")
      send_resp(conn, 200, "ok")
    else
      dispatch(conn, webhook_secret)
    end
  end

  defp dispatch(conn, webhook_secret) do
    raw_body = conn.assigns[:raw_body] || ""
    sig_header = get_req_header(conn, "stripe-signature") |> List.first()

    Ledgr.Domain.put_current(Ledgr.Domains.AumentaMiPension)
    Ledgr.Repo.put_active_repo(Ledgr.Repos.AumentaMiPension)

    case Stripe.Webhook.construct_event(raw_body, sig_header, webhook_secret) do
      {:ok, %Stripe.Event{type: type}} ->
        Logger.info("[AumentaMiPension] Stripe webhook received: #{type} (sync not yet implemented)")
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.warning("[AumentaMiPension] Stripe webhook signature verification failed: #{inspect(reason)}")
        send_resp(conn, 400, "bad request")
    end
  end
end
