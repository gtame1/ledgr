defmodule Ledgr.Domains.AumentaMiPension.StripeSync do
  @moduledoc """
  Syncs completed Stripe Checkout Sessions into the AumentaMiPension database.

  AMP uses its own Stripe account (separate from the main Ledgr account and
  HelloDoctor), so every Stripe API call passes the AMP-specific api_key
  explicitly. Since the account is AMP-only, we don't need a product-ID filter
  like HelloDoctor does — every completed session is an AMP payment.

  Payments are stored in the `stripe_payments` table (domain-local). If
  metadata carries a `consultation_id` or `conversation_id`, the linked
  consultation is updated too and an accounting journal entry is recorded.
  """

  require Logger

  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.StripePayments.StripePayment
  alias Ledgr.Domains.AumentaMiPension.Consultations.Consultation
  alias Ledgr.Core.Accounting

  @doc """
  Fetches recent completed checkout sessions from AMP's Stripe account and
  upserts them into the local `stripe_payments` table. Returns
  `{:ok, count_synced}`.
  """
  def sync_recent_payments(opts \\ []) do
    api_key = Application.get_env(:ledgr, :aumenta_mi_pension_stripe_api_key)

    if is_nil(api_key) do
      Logger.warning("[AumentaMiPension StripeSync] No API key configured")
      {:error, :no_api_key}
    else
      limit = opts[:limit] || 100

      params = %{
        limit: limit,
        status: "complete"
      }

      case Stripe.Checkout.Session.list(params, api_key: api_key) do
        {:ok, %{data: sessions}} ->
          synced =
            sessions
            |> Enum.filter(&(&1.payment_status in ["paid", "unpaid"]))
            |> Enum.map(&upsert_payment(&1, api_key))
            |> Enum.count(&match?({:ok, %StripePayment{}}, &1))

          Logger.info("[AumentaMiPension StripeSync] Synced #{synced} payments from Stripe")
          {:ok, synced}

        {:error, err} ->
          Logger.error("[AumentaMiPension StripeSync] Failed to fetch sessions: #{inspect(err)}")
          {:error, err}
      end
    end
  end

  @doc """
  Refreshes a payment row from Stripe and updates local status if it changed.
  """
  def sync_payment_status(%StripePayment{} = payment) do
    api_key = Application.get_env(:ledgr, :aumenta_mi_pension_stripe_api_key)

    with pi_id when not is_nil(pi_id) <- payment.stripe_payment_intent_id,
         {:ok, pi} <- Stripe.PaymentIntent.retrieve(pi_id, %{expand: ["latest_charge"]}, api_key: api_key) do
      charge = pi.latest_charge

      stripe_status =
        cond do
          charge && Map.get(charge, :refunded) == true -> "refunded"
          charge && (Map.get(charge, :amount_refunded) || 0) > 0 -> "refunded"
          pi.status == "succeeded" -> "paid"
          pi.status == "canceled" -> "canceled"
          true -> payment.status
        end

      product_name =
        if is_nil(payment.product_name) && payment.stripe_session_id do
          {name, _} = fetch_line_item_info(%{id: payment.stripe_session_id}, api_key)
          name
        end

      updates = %{status: stripe_status}
      updates = if product_name, do: Map.put(updates, :product_name, product_name), else: updates

      if stripe_status != payment.status || product_name do
        payment |> StripePayment.changeset(updates) |> Repo.update()
        Logger.info("[AumentaMiPension StripeSync] Payment #{payment.id} updated: status=#{stripe_status}, product=#{product_name || "unchanged"}")
        {:ok, :updated, stripe_status}
      else
        {:ok, :unchanged}
      end
    else
      nil -> {:error, :no_payment_intent}
      {:error, err} -> {:error, err}
    end
  end

  @doc """
  Public entry point used by the webhook controller to record a payment as it
  arrives. Grabs the API key from app env and delegates.
  """
  def upsert_payment(session) do
    api_key = Application.get_env(:ledgr, :aumenta_mi_pension_stripe_api_key)
    upsert_payment(session, api_key)
  end

  defp upsert_payment(session, api_key) do
    case Repo.get_by(StripePayment, stripe_session_id: session.id) do
      nil ->
        {product_name, _product_ids} = fetch_line_item_info(session, api_key)

        amount_pesos = (session.amount_total || 0) / 100.0
        customer_email = session.customer_details && session.customer_details.email
        customer_name = session.customer_details && session.customer_details.name

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

        {fee_cents, payment_status} = fetch_fee_and_status(session, api_key)
        fee_pesos = if fee_cents, do: fee_cents / 100.0, else: nil

        attrs = %{
          stripe_session_id: session.id,
          stripe_payment_intent_id: session.payment_intent,
          amount: amount_pesos,
          currency: session.currency || "mxn",
          status: payment_status,
          customer_email: customer_email,
          customer_name: customer_name,
          consultation_id: consultation_id,
          stripe_fee: fee_pesos,
          product_name: product_name,
          paid_at:
            DateTime.from_unix!(session.created)
            |> DateTime.to_naive()
            |> NaiveDateTime.truncate(:second)
        }

        case %StripePayment{}
             |> StripePayment.changeset(attrs)
             |> Repo.insert() do
          {:ok, payment} ->
            if consultation_id do
              link_to_consultation(consultation_id, amount_pesos, session.id, payment.paid_at, session.payment_intent)
            end

            create_payment_journal_entry(payment)

            {:ok, payment}

          {:error, changeset} ->
            Logger.warning("[AumentaMiPension StripeSync] Failed to insert payment for session #{session.id}: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      _existing ->
        {:ok, :already_exists}
    end
  end

  defp link_to_consultation(consultation_id, amount_pesos, _session_id, paid_at, payment_intent_id) do
    case Repo.get(Consultation, consultation_id) do
      nil ->
        :ok

      consultation ->
        consultation
        |> Ecto.Changeset.change(%{
          payment_status: "paid",
          payment_amount: amount_pesos,
          payment_confirmed_at: paid_at,
          stripe_payment_intent_id: payment_intent_id
        })
        |> Repo.update()
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
        description: "Payment from #{payment.customer_name || payment.customer_email || "customer"}",
        payee: payment.customer_name || payment.customer_email
      }

      lines = [
        %{account_id: stripe_receivable.id, debit_cents: amount_cents, credit_cents: 0,
          description: "Stripe payment received"},
        %{account_id: consultation_revenue.id, debit_cents: 0, credit_cents: amount_cents,
          description: "Consultation revenue"}
      ]

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

      # Agent payout split deferred — we don't yet know the AMP agent commission
      # rate. Revenue is recognized in full; when the commission model is
      # finalized, add a reclass entry like HelloDoctor's doctor_payable split.

      Accounting.create_journal_entry_with_lines(entry_attrs, lines)
    rescue
      e ->
        Logger.warning("[AumentaMiPension StripeSync] Failed to create journal entry for payment #{payment.id}: #{inspect(e)}")
        :ok
    end
  end

  defp fetch_fee_and_status(session, api_key) do
    if session.payment_intent do
      try do
        case Stripe.PaymentIntent.retrieve(session.payment_intent, %{expand: ["latest_charge"]}, api_key: api_key) do
          {:ok, pi} ->
            charge = pi.latest_charge

            status =
              cond do
                charge && Map.get(charge, :refunded) == true -> "refunded"
                charge && (Map.get(charge, :amount_refunded) || 0) > 0 -> "refunded"
                pi.status == "succeeded" -> "paid"
                pi.status == "canceled" -> "canceled"
                true -> "paid"
              end

            bt_id = charge && Map.get(charge, :balance_transaction)

            fee =
              if bt_id do
                bt_id = if is_binary(bt_id), do: bt_id, else: bt_id.id

                case Stripe.BalanceTransaction.retrieve(bt_id, %{}, api_key: api_key) do
                  {:ok, bt} -> bt.fee
                  _ -> nil
                end
              end

            {fee, status}

          _ ->
            {nil, "paid"}
        end
      rescue
        _ -> {nil, "paid"}
      end
    else
      {nil, "paid"}
    end
  end

  defp fetch_line_item_info(session, api_key) do
    try do
      case Stripe.Checkout.Session.retrieve(session.id, %{expand: ["line_items"]}, api_key: api_key) do
        {:ok, full_session} ->
          items = get_in(full_session, [:line_items, :data]) || []

          product_name =
            items
            |> Enum.map(& &1.description)
            |> Enum.reject(&is_nil/1)
            |> Enum.join(", ")
            |> case do
              "" -> nil
              name -> name
            end

          product_ids =
            items
            |> Enum.map(fn item ->
              case Map.get(item, :price) do
                nil ->
                  nil

                price ->
                  case Map.get(price, :product) do
                    pid when is_binary(pid) -> pid
                    %{id: id} -> id
                    _ -> nil
                  end
              end
            end)
            |> Enum.reject(&is_nil/1)

          {product_name, product_ids}

        _ ->
          {nil, []}
      end
    rescue
      _ -> {nil, []}
    end
  end

  defp find_consultation_by_conversation(conversation_id) do
    Consultation
    |> where([c], c.conversation_id == ^conversation_id)
    |> order_by(desc: :assigned_at)
    |> limit(1)
    |> select([c], c.id)
    |> Repo.one()
  end
end
