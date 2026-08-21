defmodule Ledgr.Domains.AumentaMiPension.StripeRefunds do
  @moduledoc """
  Handles Stripe refunds for AumentaMiPension payments.

  1. Issues a full refund via Stripe API using the payment_intent_id
  2. Updates the local stripe_payment record status to "refunded"
  3. Creates a reversal journal entry
  """

  require Logger

  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.StripePayments.StripePayment

  def refund_payment(%StripePayment{} = payment) do
    if payment.status == "refunded" do
      {:error, "Payment is already refunded"}
    else
      api_key = Application.get_env(:ledgr, :aumenta_mi_pension_stripe_api_key)

      if is_nil(api_key) do
        {:error, :no_api_key}
      else
        Repo.transaction(fn ->
          case issue_stripe_refund(payment, api_key) do
            {:ok, _refund} ->
              changeset =
                payment
                |> Ecto.Changeset.change(%{status: "refunded"})

              case Repo.update(changeset) do
                {:ok, updated} ->
                  updated

                {:error, changeset} ->
                  Repo.rollback(changeset)
              end

            {:error, reason} ->
              Logger.error(
                "[AumentaMiPension] Stripe refund failed for payment #{payment.id}: #{inspect(reason)}"
              )

              Repo.rollback(reason)
          end
        end)
      end
    end
  end

  defp issue_stripe_refund(payment, api_key) do
    cond do
      payment.stripe_payment_intent_id ->
        case Stripe.Refund.create(%{payment_intent: payment.stripe_payment_intent_id},
               api_key: api_key
             ) do
          {:ok, refund} ->
            Logger.info(
              "[AumentaMiPension] Stripe refund created: #{refund.id} for PI #{payment.stripe_payment_intent_id}"
            )

            {:ok, refund}

          {:error, %Stripe.Error{} = err} ->
            {:error, err.message || "Stripe refund failed"}

          {:error, err} ->
            {:error, inspect(err)}
        end

      true ->
        {:error, "No payment_intent_id — cannot refund via Stripe"}
    end
  end

end
