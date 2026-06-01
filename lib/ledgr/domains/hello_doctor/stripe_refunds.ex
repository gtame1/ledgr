defmodule Ledgr.Domains.HelloDoctor.StripeRefunds do
  @moduledoc """
  Handles Stripe refunds for HelloDoctor payments.

  1. Issues a full refund via Stripe API using the payment_intent_id
  2. Updates the local stripe_payment record status to "refunded"
  3. Creates a reversal journal entry

  ## The `pay_doctor` override

  By default a full refund reverses the doctor payable along with revenue
  and receivable — i.e., we don't owe the doctor for a refunded session.
  Pass `pay_doctor: true` to override that on a case-by-case basis (bad
  patient experience that wasn't the doctor's fault, etc.); the JE
  leaves Doctor Payable intact so the doctor stays owed their flat share
  and HD absorbs the full refund as a loss.

  The decision is locked in at refund time and not stored separately —
  if you change your mind later, you'll need to post a manual JE to
  flip Doctor Payable in the other direction.
  """

  require Logger

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting
  alias Ledgr.Domains.HelloDoctor.ConsultationPayoutDecisions
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry

  import Ecto.Query, only: [from: 2]

  @doc """
  Issues a full Stripe refund + posts the reversal JE.

  Options:
    * `:pay_doctor` — when `true`, the doctor payable is *not* reversed;
      the doctor stays owed their flat share despite the refund.
      Default `false` (matches historical behavior).
  """
  def refund_payment(%StripePayment{} = payment, opts \\ []) do
    pay_doctor? = Keyword.get(opts, :pay_doctor, false)

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
                  # 3. Record the pay-doctor decision (sidecar table).
                  # `pay_doctor?=true` means "still pay" (the override);
                  # `false` means default behavior on refund.
                  if updated.consultation_id do
                    ConsultationPayoutDecisions.upsert(
                      updated.consultation_id,
                      pay_doctor?,
                      reason:
                        if(pay_doctor?,
                          do: "refund_override: still pay doctor",
                          else: "refund: doctor payable reversed"
                        ),
                      decided_by: "system"
                    )
                  end

                  # 4. Create reversal journal entry, respecting the
                  # pay_doctor override (only meaningful for full refunds).
                  create_refund_journal_entry(updated, pay_doctor: pay_doctor?)
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

  Called both from `refund_payment/2` (initiated in Ledgr) and from the
  Stripe webhook when a refund originates outside Ledgr (e.g. from
  Stripe dashboard). Idempotent — skips if a journal entry with the
  same reference already exists.

  Options:
    * `:pay_doctor` — when `true`, the doctor payable is *not* reversed
      even on a full refund. Defaults to `false`. Only meaningful for
      full refunds (partial refunds always leave doctor payable intact).

  Refund logic:
  - **Full refund**, `pay_doctor: false` (default): reverse revenue,
    receivable, *and* doctor payable. Net effect on doctor: $0 owed.
  - **Full refund**, `pay_doctor: true`: reverse revenue + receivable
    only. Doctor stays owed their flat share; HD absorbs the entire
    refund as a loss.
  - **Partial refund**: reverse revenue + receivable proportionally;
    doctor payable always left intact (`pay_doctor` is a no-op here).

  The Stripe processing fee was booked as an expense at payment time
  (account 6000) and is *not* refunded by Stripe — so no further fee
  bookkeeping is required here. The original fee stays as an expense.
  """
  def create_refund_journal_entry(%StripePayment{} = payment, opts \\ []) do
    reference = "Refund for #{payment.stripe_session_id}"

    cond do
      refund_already_recorded?(reference) ->
        {:ok, :already_recorded}

      true ->
        do_create_refund_journal_entry(payment, reference, opts)
    end
  end

  defp do_create_refund_journal_entry(payment, reference, opts) do
    pay_doctor? = Keyword.get(opts, :pay_doctor, false)

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

      desc_suffix =
        cond do
          full_refund? && pay_doctor? -> " — doctor paid anyway (override)"
          true -> ""
        end

      entry_attrs = %{
        date: Date.utc_today(),
        entry_type: "refund",
        reference: reference,
        description:
          "#{if full_refund?, do: "Refund", else: "Partial refund"} to " <>
            "#{payment.customer_name || payment.customer_email || "patient"}" <>
            desc_suffix,
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

      # Reverse doctor payable only when (a) it's a full refund AND (b) the
      # operator didn't opt to pay the doctor anyway. Partial refunds and
      # explicit pay-doctor overrides both leave the doctor payable intact.
      lines =
        if full_refund? and not pay_doctor? do
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
