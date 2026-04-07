defmodule Ledgr.Domains.HelloDoctor.ConsultationAccounting do
  @moduledoc """
  Accounting integration for HelloDoctor consultations.

  When a patient pays for a consultation (via Stripe), this module creates
  the double-entry journal entries:

  1. Revenue recognition:
     DEBIT  1200 Stripe Receivable     $500   (money coming from Stripe)
     CREDIT 4000 Consultation Revenue  $500   (full amount as revenue)

  2. Stripe processing fee:
     DEBIT  6000 Payment Processing    $21    (actual Stripe fee)
     CREDIT 1200 Stripe Receivable     $21    (deducted from receivable)

  3. Doctor payout (85%):
     DEBIT  4000 Consultation Revenue  $425   (reclassify doctor's share)
     CREDIT 2000 Doctor Payable        $425   (owe doctor 85%)

  Net result: HelloDoctor keeps 15% commission minus Stripe fees.
  """

  require Logger

  alias Ledgr.Core.Accounting

  # Account codes from HelloDoctor domain config
  @stripe_receivable_code "1200"
  @consultation_revenue_code "4000"
  @payment_processing_code "6000"
  @doctor_payable_code "2000"

  @commission_rate 0.15

  @doc """
  Records a consultation payment as journal entries.

  `consultation` must have patient and doctor preloaded.
  `amount_pesos` is the total payment amount in pesos (float).
  """
  def record_payment(consultation, amount_pesos, opts \\ []) do
    amount_cents = round(amount_pesos * 100)
    commission_cents = round(amount_cents * @commission_rate)
    doctor_payout_cents = amount_cents - commission_cents

    stripe_session_id = opts[:stripe_session_id]

    # Fetch actual Stripe fee if we have a session ID
    fee_cents = fetch_stripe_fee_cents(stripe_session_id) || estimate_stripe_fee_cents(amount_cents)

    patient_name =
      if consultation.patient do
        consultation.patient.full_name || consultation.patient.display_name || "Patient"
      else
        "Patient"
      end

    doctor_name =
      if consultation.doctor do
        consultation.doctor.name || "Doctor"
      else
        "Unassigned"
      end

    # Look up accounts
    stripe_receivable = Accounting.get_account_by_code!(@stripe_receivable_code)
    consultation_revenue = Accounting.get_account_by_code!(@consultation_revenue_code)
    payment_processing = Accounting.get_account_by_code!(@payment_processing_code)
    doctor_payable = Accounting.get_account_by_code!(@doctor_payable_code)

    entry_attrs = %{
      date: Date.utc_today(),
      entry_type: "consultation_payment",
      reference: "Consultation #{consultation.id}",
      description: "Payment from #{patient_name} — Dr. #{doctor_name}",
      payee: patient_name
    }

    lines = [
      # 1. Revenue recognition: Stripe Receivable <- Consultation Revenue
      %{
        account_id: stripe_receivable.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Stripe payment received for consultation #{consultation.id}"
      },
      %{
        account_id: consultation_revenue.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Consultation revenue — #{patient_name}"
      },
      # 2. Stripe fee
      %{
        account_id: payment_processing.id,
        debit_cents: fee_cents,
        credit_cents: 0,
        description: "Stripe processing fee for consultation #{consultation.id}"
      },
      %{
        account_id: stripe_receivable.id,
        debit_cents: 0,
        credit_cents: fee_cents,
        description: "Stripe fee deducted from receivable"
      },
      # 3. Doctor payout (85%): reclassify from revenue to payable
      %{
        account_id: consultation_revenue.id,
        debit_cents: doctor_payout_cents,
        credit_cents: 0,
        description: "Doctor's share (85%) — Dr. #{doctor_name}"
      },
      %{
        account_id: doctor_payable.id,
        debit_cents: 0,
        credit_cents: doctor_payout_cents,
        description: "Owed to Dr. #{doctor_name} for consultation #{consultation.id}"
      }
    ]

    case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
      {:ok, entry} ->
        Logger.info("[HelloDoctor] Created journal entry ##{entry.id} for consultation #{consultation.id}: $#{amount_pesos} MXN")
        {:ok, entry}

      {:error, changeset} ->
        Logger.error("[HelloDoctor] Failed to create journal entry for consultation #{consultation.id}: #{inspect(changeset)}")
        {:error, changeset}
    end
  end

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
              case Stripe.PaymentIntent.retrieve(payment_intent_id, %{expand: ["latest_charge"]}, api_key: api_key) do
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

                _ -> nil
              end
            else
              nil
            end

          _ -> nil
        end
      rescue
        e ->
          Logger.warning("[HelloDoctor] Failed to fetch Stripe fee for session #{session_id}: #{inspect(e)}")
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
