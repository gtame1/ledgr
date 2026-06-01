defmodule LedgrWeb.HelloDoctorStripeWebhookController do
  use LedgrWeb, :controller

  require Logger

  alias Ledgr.Domains.HelloDoctor.StripeSync
  alias Ledgr.Domains.HelloDoctor.StripeRefunds
  alias Ledgr.Domains.HelloDoctor.StripePayouts
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment

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

      {:ok, %Stripe.Event{type: "charge.updated", data: %{object: charge}}} ->
        handle_charge_updated(conn, charge)

      {:ok, %Stripe.Event{type: "payout.paid", data: %{object: payout}}} ->
        handle_payout(conn, payout)

      {:ok, %Stripe.Event{type: type}} ->
        Logger.debug("[HelloDoctor] Stripe webhook: unhandled event type #{type}")
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.warning(
          "[HelloDoctor] Stripe webhook signature verification failed: #{inspect(reason)}"
        )

        send_resp(conn, 400, "bad request")
    end
  end

  defp handle_checkout_completed(conn, session) do
    amount_pesos = (session.amount_total || 0) / 100.0
    metadata = session.metadata || %{}

    Logger.info(
      "[HelloDoctor] Stripe checkout completed: session=#{session.id}, amount=$#{amount_pesos}, metadata=#{inspect(metadata)}"
    )

    case StripeSync.upsert_payment(session) do
      {:ok, :already_exists} ->
        Logger.info(
          "[HelloDoctor] Stripe webhook: payment for session #{session.id} already recorded, skipping"
        )

        send_resp(conn, 200, "ok — already recorded")

      {:ok, payment} ->
        link_info =
          if payment.consultation_id,
            do: " (linked to consultation #{payment.consultation_id})",
            else: " (unlinked — no metadata)"

        Logger.info(
          "[HelloDoctor] Stripe webhook: recorded payment for session #{session.id}, amount: $#{amount_pesos}#{link_info}"
        )

        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.error(
          "[HelloDoctor] Stripe webhook: failed to record payment for session #{session.id}: #{inspect(reason)}"
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
      amount_refunded_cents = Map.get(charge, :amount_refunded, 0) || 0
      amount_refunded_pesos = amount_refunded_cents / 100.0

      case Ledgr.Repo.get_by(StripePayment, stripe_payment_intent_id: payment_intent_id) do
        nil ->
          Logger.warning(
            "[HelloDoctor] Stripe webhook: charge.refunded for unknown payment_intent #{payment_intent_id}"
          )

        %StripePayment{} = payment ->
          original_cents = round(payment.amount * 100)
          full_refund? = amount_refunded_cents >= original_cents
          new_status = if full_refund?, do: "refunded", else: "partially_refunded"

          # Refund-via-webhook (typically Stripe-dashboard-initiated) has no
          # UI for the "Still pay doctor" override — so default to false on
          # a full refund, matching the JE-side default. Partial refunds
          # always leave pay_doctor as-is (doctor performed the work).
          pay_doctor_update =
            if full_refund?, do: %{pay_doctor: false}, else: %{}

          # Update amount_refunded + status (idempotent — same values on retry).
          # The refund JE creator is itself idempotent via the reference check.
          {:ok, updated} =
            payment
            |> StripePayment.changeset(
              Map.merge(
                %{status: new_status, amount_refunded: amount_refunded_pesos},
                pay_doctor_update
              )
            )
            |> Ledgr.Repo.update()

          StripeRefunds.create_refund_journal_entry(updated)

          Logger.info(
            "[HelloDoctor] Stripe webhook: payment #{payment.id} refunded $#{amount_refunded_pesos} (#{new_status}) — JE ensured (charge #{charge.id})"
          )
      end
    else
      Logger.warning(
        "[HelloDoctor] Stripe webhook: charge.refunded with no payment_intent (charge #{charge.id})"
      )
    end

    send_resp(conn, 200, "ok")
  end

  # ── charge.updated ──────────────────────────────────────────────
  #
  # Stripe fires `charge.updated` whenever a charge changes — most
  # importantly, once the balance_transaction (and therefore the fee)
  # becomes available. checkout.session.completed often runs before the
  # BT exists, so the initial upsert lands with stripe_fee=NULL. This
  # handler fills it in.
  #
  # IMPORTANT: this requires `charge.updated` to be enabled in the
  # Stripe webhook endpoint config. Without it, NULL fees still need the
  # manual /payments/backfill-fees button.
  #
  # Idempotent — only updates rows whose stripe_fee is currently NULL,
  # and silently no-ops when the BT isn't published yet (Stripe will
  # fire another charge.updated when it is).
  defp handle_charge_updated(conn, charge) do
    pi_id = extract_id(Map.get(charge, :payment_intent))
    bt_id = extract_id(Map.get(charge, :balance_transaction))

    cond do
      is_nil(pi_id) ->
        send_resp(conn, 200, "ok — no payment_intent")

      is_nil(bt_id) ->
        # BT not yet published. Stripe will fire again later.
        send_resp(conn, 200, "ok — balance_transaction not ready")

      true ->
        case Ledgr.Repo.get_by(StripePayment, stripe_payment_intent_id: pi_id) do
          nil ->
            Logger.debug(
              "[HelloDoctor] charge.updated for unknown payment_intent #{pi_id} (charge #{charge.id})"
            )

            send_resp(conn, 200, "ok — unknown payment")

          %StripePayment{stripe_fee: existing_fee} = payment
          when is_nil(existing_fee) or existing_fee == 0.0 ->
            populate_fee(conn, payment, bt_id)

          %StripePayment{} ->
            # Fee already populated — leave it alone.
            send_resp(conn, 200, "ok — fee already set")
        end
    end
  end

  defp populate_fee(conn, payment, bt_id) do
    api_key = Application.get_env(:ledgr, :hello_doctor_stripe_api_key)

    case Stripe.BalanceTransaction.retrieve(bt_id, %{}, api_key: api_key) do
      {:ok, %{fee: fee_cents}} when is_integer(fee_cents) and fee_cents > 0 ->
        fee_pesos = fee_cents / 100.0

        case payment
             |> StripePayment.changeset(%{stripe_fee: fee_pesos})
             |> Ledgr.Repo.update() do
          {:ok, _} ->
            Logger.info(
              "[HelloDoctor] charge.updated populated fee for payment #{payment.id}: $#{fee_pesos} MXN"
            )

            send_resp(conn, 200, "ok")

          {:error, changeset} ->
            Logger.error(
              "[HelloDoctor] Failed to save fee for payment #{payment.id}: #{inspect(changeset.errors)}"
            )

            send_resp(conn, 500, "error")
        end

      {:ok, _} ->
        # BT exists but fee is 0 / not yet calculated. Try again on the next event.
        send_resp(conn, 200, "ok — fee not yet calculated")

      {:error, reason} ->
        Logger.warning(
          "[HelloDoctor] Failed to fetch balance_transaction #{bt_id}: #{inspect(reason)}"
        )

        send_resp(conn, 500, "error")
    end
  end

  defp extract_id(nil), do: nil
  defp extract_id(id) when is_binary(id), do: id
  defp extract_id(%{id: id}), do: id
  defp extract_id(_), do: nil

  defp handle_payout(conn, payout) do
    Logger.info(
      "[HelloDoctor] Stripe payout.paid: #{payout.id}, amount=$#{(payout.amount || 0) / 100} " <>
        "#{String.upcase(payout.currency || "")}"
    )

    case StripePayouts.upsert_payout(payout) do
      {:ok, :already_recorded} ->
        send_resp(conn, 200, "ok — already recorded")

      {:ok, :no_consultation_amount} ->
        Logger.info(
          "[HelloDoctor] Payout #{payout.id} had no consultation activity (Retos-only) — skipped"
        )

        send_resp(conn, 200, "ok — skipped (non-consultation payout)")

      {:ok, _entry} ->
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.error("[HelloDoctor] Failed to record payout #{payout.id}: #{inspect(reason)}")

        send_resp(conn, 500, "error")
    end
  end
end
