defmodule Ledgr.Domains.HelloDoctor.StripeFees do
  @moduledoc """
  The processing fee Stripe charged on a payment.

  Extracted from `ConsultationAccounting`. These are Stripe API and pricing
  helpers — nothing to do with the general ledger — and they outlive it.
  """

  require Logger

  @doc """
  Fetches the actual Stripe fee from the Balance Transaction API.
  Uses the HelloDoctor-specific API key.
  """
  def fetch_stripe_fee_cents(nil), do: nil

  def fetch_stripe_fee_cents(session_id) do
    api_key = Application.get_env(:ledgr, :hello_doctor_stripe_api_key)

    if is_nil(api_key) do
      nil
    else
      try do
        # Get the payment intent from the session
        case Stripe.Checkout.Session.retrieve(session_id, %{}, api_key: api_key) do
          {:ok, session} ->
            payment_intent_id = session.payment_intent

            if payment_intent_id do
              case Stripe.PaymentIntent.retrieve(payment_intent_id, %{expand: ["latest_charge"]},
                     api_key: api_key
                   ) do
                {:ok, pi} ->
                  charge = pi.latest_charge

                  if charge && charge.balance_transaction do
                    bt_id =
                      if is_binary(charge.balance_transaction),
                        do: charge.balance_transaction,
                        else: charge.balance_transaction.id

                    case Stripe.BalanceTransaction.retrieve(bt_id, %{}, api_key: api_key) do
                      {:ok, bt} -> bt.fee
                      _ -> nil
                    end
                  else
                    nil
                  end

                _ ->
                  nil
              end
            else
              nil
            end

          _ ->
            nil
        end
      rescue
        e ->
          Logger.warning(
            "[HelloDoctor] Failed to fetch Stripe fee for session #{session_id}: #{inspect(e)}"
          )

          nil
      end
    end
  end

  @doc """
  Estimates Stripe fee using Mexico pricing: 3.6% + $3 MXN + 16% IVA.
  Returns fee in centavos.
  """
  def estimate_stripe_fee_cents(amount_cents) do
    base_fee = amount_cents * 0.036 + 300
    fee_with_iva = base_fee * 1.16
    round(fee_with_iva)
  end
end
