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
  alias Ledgr.Core.Accounting

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
                  create_refund_journal_entry(updated)
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

  defp create_refund_journal_entry(%StripePayment{} = payment) do
    try do
      amount_cents = round(payment.amount * 100)

      stripe_receivable = Accounting.get_account_by_code!("1200")
      consultation_revenue = Accounting.get_account_by_code!("4000")
      refunds_expense = Accounting.get_account_by_code!("6010")

      entry_attrs = %{
        date: Date.utc_today(),
        entry_type: "refund",
        reference: "Refund for #{payment.stripe_session_id}",
        description: "Refund to #{payment.customer_name || payment.customer_email || "customer"}",
        payee: payment.customer_name || payment.customer_email
      }

      lines = [
        # Reverse the revenue recognition
        %{
          account_id: consultation_revenue.id,
          debit_cents: amount_cents,
          credit_cents: 0,
          description: "Reverse consultation revenue (refund)"
        },
        %{
          account_id: stripe_receivable.id,
          debit_cents: 0,
          credit_cents: amount_cents,
          description: "Reduce Stripe receivable (refund sent)"
        },
        # Record refund expense (Stripe doesn't refund the processing fee)
        %{
          account_id: refunds_expense.id,
          debit_cents: round((payment.stripe_fee || 0) * 100),
          credit_cents: 0,
          description: "Stripe fee lost on refund (non-refundable)"
        },
        %{
          account_id: stripe_receivable.id,
          debit_cents: round((payment.stripe_fee || 0) * 100),
          credit_cents: 0,
          description: "Stripe fee adjustment on receivable"
        }
      ]

      # Filter out zero-amount fee lines
      lines = Enum.reject(lines, fn l -> l.debit_cents == 0 && l.credit_cents == 0 end)

      Accounting.create_journal_entry_with_lines(entry_attrs, lines)
    rescue
      e ->
        Logger.warning(
          "[AumentaMiPension] Failed to create refund journal entry for payment #{payment.id}: #{inspect(e)}"
        )

        :ok
    end
  end
end
