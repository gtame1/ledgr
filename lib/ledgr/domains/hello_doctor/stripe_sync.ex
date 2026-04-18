defmodule Ledgr.Domains.HelloDoctor.StripeSync do
  @moduledoc """
  Syncs completed Stripe Checkout Sessions into the HelloDoctor database.

  Since the WhatsApp bot sends static payment links (without consultation_id
  metadata), we poll the Stripe API for completed sessions and store them
  locally. This gives us a reliable record of all payments received.

  Payments are stored in the `stripe_payments` table (HelloDoctor-specific).
  If a consultation_id IS present in metadata, the corresponding consultation
  is also updated.
  """

  require Logger

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment
  alias Ledgr.Domains.HelloDoctor.Consultations
  alias Ledgr.Core.Accounting

  @doc """
  Fetches recent completed checkout sessions from Stripe and upserts them
  into the local stripe_payments table. Returns {:ok, count_synced}.
  """
  # Only sync payments created on or after 2026-01-01
  @sync_from_unix 1_735_689_600

  def sync_recent_payments(opts \\ []) do
    api_key = Application.get_env(:ledgr, :hello_doctor_stripe_api_key)

    if is_nil(api_key) do
      Logger.warning("[HelloDoctor StripeSync] No API key configured")
      {:error, :no_api_key}
    else
      limit = opts[:limit] || 100

      params = %{
        limit: limit,
        status: "complete",
        created: %{gte: @sync_from_unix}
      }

      case Stripe.Checkout.Session.list(params, api_key: api_key) do
        {:ok, %{data: sessions}} ->
          synced =
            sessions
            |> Enum.filter(&(&1.payment_status == "paid"))
            |> Enum.map(&upsert_payment(&1, api_key))
            |> Enum.count(&match?({:ok, _}, &1))

          Logger.info("[HelloDoctor StripeSync] Synced #{synced} payments from Stripe")
          {:ok, synced}

        {:error, err} ->
          Logger.error("[HelloDoctor StripeSync] Failed to fetch sessions: #{inspect(err)}")
          {:error, err}
      end
    end
  end

  @doc """
  Public entry point for upserting a single Stripe session — used by the
  webhook controller to record payments as they come in.
  """
  def upsert_payment(session) do
    api_key = Application.get_env(:ledgr, :hello_doctor_stripe_api_key)
    upsert_payment(session, api_key)
  end

  defp upsert_payment(session, api_key) do
    case Repo.get_by(StripePayment, stripe_session_id: session.id) do
      nil ->
        # New payment — insert
        amount_pesos = (session.amount_total || 0) / 100.0
        customer_email = session.customer_details && session.customer_details.email
        customer_name = session.customer_details && session.customer_details.name
        # Bot sends conversation_id in metadata — look up the consultation via conversation
        metadata = session.metadata || %{}
        consultation_id =
          cond do
            metadata["consultation_id"] ->
              metadata["consultation_id"]
            metadata["conversation_id"] ->
              find_consultation_by_conversation(metadata["conversation_id"])
            true ->
              nil
          end

        # Try to fetch actual Stripe fee
        fee_cents = fetch_fee(session, api_key)
        fee_pesos = if fee_cents, do: fee_cents / 100.0, else: nil

        attrs = %{
          stripe_session_id: session.id,
          stripe_payment_intent_id: session.payment_intent,
          amount: amount_pesos,
          currency: session.currency || "mxn",
          status: "paid",
          customer_email: customer_email,
          customer_name: customer_name,
          consultation_id: consultation_id,
          stripe_fee: fee_pesos,
          paid_at: DateTime.from_unix!(session.created) |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
        }

        case %StripePayment{}
             |> StripePayment.changeset(attrs)
             |> Repo.insert() do
          {:ok, payment} ->
            # If we have a consultation_id, update the consultation too
            if consultation_id do
              link_to_consultation(consultation_id, amount_pesos, session.id)
            end

            # Create accounting journal entry
            create_payment_journal_entry(payment)

            {:ok, payment}

          {:error, changeset} ->
            Logger.warning("[HelloDoctor StripeSync] Failed to insert payment for session #{session.id}: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      _existing ->
        # Already synced
        {:ok, :already_exists}
    end
  end

  defp link_to_consultation(consultation_id, amount_pesos, session_id) do
    case Consultations.get_consultation(consultation_id) do
      nil -> :ok
      consultation ->
        Consultations.record_stripe_payment(consultation, %{
          payment_amount: amount_pesos,
          stripe_session_id: session_id
        })
    end
  end

  defp create_payment_journal_entry(%StripePayment{} = payment) do
    try do
      stripe_receivable = Accounting.get_account_by_code!("1200")
      consultation_revenue = Accounting.get_account_by_code!("4000")

      amount_cents = round(payment.amount * 100)

      entry_attrs = %{
        date: payment.paid_at |> NaiveDateTime.to_date(),
        entry_type: "consultation_payment",
        reference: "Stripe #{payment.stripe_session_id}",
        description: "Payment from #{payment.customer_name || payment.customer_email || "patient"}",
        payee: payment.customer_name || payment.customer_email
      }

      lines = [
        %{account_id: stripe_receivable.id, debit_cents: amount_cents, credit_cents: 0,
          description: "Stripe payment received"},
        %{account_id: consultation_revenue.id, debit_cents: 0, credit_cents: amount_cents,
          description: "Consultation revenue"}
      ]

      # Add fee lines if we have the fee
      lines =
        if payment.stripe_fee && payment.stripe_fee > 0 do
          fee_cents = round(payment.stripe_fee * 100)
          processing = Accounting.get_account_by_code!("6000")

          lines ++ [
            %{account_id: processing.id, debit_cents: fee_cents, credit_cents: 0,
              description: "Stripe processing fee"},
            %{account_id: stripe_receivable.id, debit_cents: 0, credit_cents: fee_cents,
              description: "Stripe fee deducted from receivable"}
          ]
        else
          lines
        end

      # Add doctor payable lines (85%)
      doctor_payable_account = Accounting.get_account_by_code("2000")

      lines =
        if doctor_payable_account do
          doctor_payout_cents = round(amount_cents * 0.85)

          lines ++ [
            %{account_id: consultation_revenue.id, debit_cents: doctor_payout_cents, credit_cents: 0,
              description: "Doctor's share (85%)"},
            %{account_id: doctor_payable_account.id, debit_cents: 0, credit_cents: doctor_payout_cents,
              description: "Owed to doctor"}
          ]
        else
          lines
        end

      Accounting.create_journal_entry_with_lines(entry_attrs, lines)
    rescue
      e ->
        Logger.warning("[HelloDoctor StripeSync] Failed to create journal entry for payment #{payment.id}: #{inspect(e)}")
        :ok
    end
  end

  defp fetch_fee(session, api_key) do
    if session.payment_intent do
      try do
        case Stripe.PaymentIntent.retrieve(session.payment_intent, %{expand: ["latest_charge"]}, api_key: api_key) do
          {:ok, pi} ->
            charge = pi.latest_charge
            bt_id = charge && charge.balance_transaction

            if bt_id do
              bt_id = if is_binary(bt_id), do: bt_id, else: bt_id.id

              case Stripe.BalanceTransaction.retrieve(bt_id, %{}, api_key: api_key) do
                {:ok, bt} -> bt.fee
                _ -> nil
              end
            end

          _ -> nil
        end
      rescue
        _ -> nil
      end
    end
  end

  defp find_consultation_by_conversation(conversation_id) do
    import Ecto.Query, warn: false
    alias Ledgr.Domains.HelloDoctor.Consultations.Consultation

    # Find the most recent consultation for this conversation
    Consultation
    |> where([c], c.conversation_id == ^conversation_id)
    |> order_by(desc: :assigned_at)
    |> limit(1)
    |> select([c], c.id)
    |> Repo.one()
  end
end
