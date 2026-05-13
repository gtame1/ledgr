defmodule Ledgr.Domains.HelloDoctor.StripeRefunds do
  @moduledoc """
  Handles Stripe refunds for HelloDoctor payments.

  1. Issues a full refund via Stripe API using the payment_intent_id
  2. Updates the local stripe_payment record status to "refunded"
  3. Creates a reversal journal entry
  """

  require Logger

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry

  import Ecto.Query, only: [from: 2]

  def refund_payment(%StripePayment{} = payment) do
    if payment.status == "refunded" do
      {:error, "Payment is already refunded"}
    else
      api_key = Application.get_env(:ledgr, :hello_doctor_stripe_api_key)

      if is_nil(api_key) do
        {:error, :no_api_key}
      else
        Repo.transaction(fn ->
          # 1. Issue Stripe refund (full refund — Stripe defaults to the
          # full charge amount when no `amount` param is given).
          case issue_stripe_refund(payment, api_key) do
            {:ok, _refund} ->
              # 2. Update local record — mark refunded and record the
              # amount refunded so the reversal JE and reports stay in sync.
              changeset =
                payment
                |> Ecto.Changeset.change(%{
                  status: "refunded",
                  amount_refunded: payment.amount
                })

              case Repo.update(changeset) do
                {:ok, updated} ->
                  # 3. Create reversal journal entry
                  create_refund_journal_entry(updated)
                  updated

                {:error, changeset} ->
                  Repo.rollback(changeset)
              end

            {:error, reason} ->
              Logger.error(
                "[HelloDoctor] Stripe refund failed for payment #{payment.id}: #{inspect(reason)}"
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
              "[HelloDoctor] Stripe refund created: #{refund.id} for PI #{payment.stripe_payment_intent_id}"
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

  @doc """
  Creates the reversal journal entry for a refunded payment.

  Called both from refund_payment/1 (initiated in Ledgr) and from the
  Stripe webhook when a refund originates outside Ledgr (e.g. from Stripe
  dashboard). Idempotent — skips if a journal entry with the same reference
  already exists.

  Refund logic:
  - **Full refund** (default): reverse both the revenue and the doctor payable.
  - **Partial refund**: reverse only the revenue (proportional to refunded
    amount). The doctor still attended the consultation, so the doctor payable
    is left intact — HD absorbs the partial refund.

  The Stripe processing fee was already booked as an expense at original
  payment time (account 6000) and is *not* refunded by Stripe — so no further
  fee bookkeeping is required here. The original fee stays as an expense.
  """
  def create_refund_journal_entry(%StripePayment{} = payment) do
    reference = "Refund for #{payment.stripe_session_id}"

    cond do
      refund_already_recorded?(reference) ->
        {:ok, :already_recorded}

      true ->
        do_create_refund_journal_entry(payment, reference)
    end
  end

  defp do_create_refund_journal_entry(payment, reference) do
    try do
      # Use amount_refunded if present (partial refund support); fall back to
      # the full amount when amount_refunded is nil/0 — that's the common case
      # for full refunds initiated before partial-refund tracking landed.
      refunded_pesos =
        case Map.get(payment, :amount_refunded) do
          n when is_number(n) and n > 0 -> n
          _ -> payment.amount
        end

      refunded_cents = round(refunded_pesos * 100)
      original_cents = round(payment.amount * 100)
      full_refund? = refunded_cents >= original_cents

      stripe_receivable = Accounting.get_account_by_code!("1200")
      consultation_revenue = Accounting.get_account_by_code!("4000")
      doctor_payable = Accounting.get_account_by_code!("2000")

      entry_attrs = %{
        date: Date.utc_today(),
        entry_type: "refund",
        reference: reference,
        description:
          "#{if full_refund?, do: "Refund", else: "Partial refund"} to " <>
            "#{payment.customer_name || payment.customer_email || "patient"}",
        payee: payment.customer_name || payment.customer_email
      }

      # Always reverse revenue and receivable by the refunded amount.
      base_lines = [
        %{
          account_id: consultation_revenue.id,
          debit_cents: refunded_cents,
          credit_cents: 0,
          description:
            "Reverse consultation revenue (#{if full_refund?, do: "refund", else: "partial refund"})"
        },
        %{
          account_id: stripe_receivable.id,
          debit_cents: 0,
          credit_cents: refunded_cents,
          description: "Reduce Stripe receivable (refund sent)"
        }
      ]

      # Only reverse doctor payable on a *full* refund. The doctor performed
      # the work on partial refunds, so they're still owed their flat share.
      lines =
        if full_refund? do
          doctor_payout_cents = ConsultationAccounting.doctor_share_cents()

          base_lines ++
            [
              %{
                account_id: doctor_payable.id,
                debit_cents: doctor_payout_cents,
                credit_cents: 0,
                description: "Reverse doctor payable (refund)"
              },
              %{
                account_id: consultation_revenue.id,
                debit_cents: 0,
                credit_cents: doctor_payout_cents,
                description: "Reverse doctor share reclassification"
              }
            ]
        else
          base_lines
        end

      Accounting.create_journal_entry_with_lines(entry_attrs, lines)
    rescue
      e ->
        Logger.warning(
          "[HelloDoctor] Failed to create refund journal entry for payment #{payment.id}: #{inspect(e)}"
        )

        :ok
    end
  end

  defp refund_already_recorded?(reference) do
    Repo.exists?(from je in JournalEntry, where: je.reference == ^reference)
  end
end
