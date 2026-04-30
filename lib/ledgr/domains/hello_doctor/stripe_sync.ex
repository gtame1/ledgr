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
  alias Ledgr.Domains.HelloDoctor.StripeRefunds
  alias Ledgr.Core.Accounting

  @doc """
  Fetches recent completed checkout sessions from Stripe and upserts them
  into the local stripe_payments table. Returns {:ok, count_synced}.

  Only sessions that contain a HelloDoctor product (matched by product ID) are
  stored — everything else from the shared Stripe account is silently skipped.
  """
  # Stripe product IDs that belong to HelloDoctor
  @hellodoctor_product_ids ["prod_UHpGzvMsR5pRZb"]

  def sync_recent_payments(opts \\ []) do
    api_key = Application.get_env(:ledgr, :hello_doctor_stripe_api_key)

    if is_nil(api_key) do
      Logger.warning("[HelloDoctor StripeSync] No API key configured")
      {:error, :no_api_key}
    else
      limit = opts[:limit] || 100

      params = %{
        limit: limit,
        status: "complete"
      }

      case Stripe.Checkout.Session.list(params, api_key: api_key) do
        {:ok, %{data: sessions}} ->
          results =
            sessions
            |> Enum.filter(&(&1.payment_status in ["paid", "unpaid"]))
            |> Enum.map(&upsert_payment(&1, api_key))

          new_count = Enum.count(results, &match?({:ok, %StripePayment{}}, &1))
          existing_count = Enum.count(results, &match?({:ok, :already_exists}, &1))
          skipped_count = Enum.count(results, &match?({:ok, :skipped}, &1))

          Logger.info(
            "[HelloDoctor StripeSync] Synced #{new_count} new, #{existing_count} already existed, #{skipped_count} skipped (non-HD product). Total sessions fetched: #{length(sessions)}"
          )

          {:ok, new_count, existing_count}

        {:error, err} ->
          Logger.error("[HelloDoctor StripeSync] Failed to fetch sessions: #{inspect(err)}")
          {:error, err}
      end
    end
  end

  @doc """
  Creates GL journal entries for any StripePayments that don't already have one.
  Safe to run multiple times — skips payments whose Stripe session ID already
  appears in a journal entry reference.
  Returns {:ok, %{posted: N, skipped: N, errors: N}}.
  """
  def backfill_journal_entries do
    import Ecto.Query, warn: false
    alias Ledgr.Core.Accounting.JournalEntry

    # Collect session IDs that already have a journal entry
    posted_refs =
      JournalEntry
      |> where([je], like(je.reference, "Stripe %"))
      |> select([je], je.reference)
      |> Repo.all()
      |> MapSet.new()

    payments = Repo.all(StripePayment)

    result =
      Enum.reduce(payments, %{posted: 0, skipped: 0, errors: 0}, fn payment, acc ->
        ref = "Stripe #{payment.stripe_session_id}"

        cond do
          MapSet.member?(posted_refs, ref) ->
            %{acc | skipped: acc.skipped + 1}

          payment.status == "refunded" ->
            # Post the refund reversal instead
            case StripeRefunds.create_refund_journal_entry(payment) do
              {:ok, _} -> %{acc | posted: acc.posted + 1}
              _ -> %{acc | errors: acc.errors + 1}
            end

          true ->
            case create_payment_journal_entry(payment) do
              {:ok, _} -> %{acc | posted: acc.posted + 1}
              _ -> %{acc | errors: acc.errors + 1}
            end
        end
      end)

    Logger.info("[HelloDoctor StripeSync] Backfill complete: #{inspect(result)}")
    {:ok, result}
  end

  @doc """
  Fetches the current status of a payment from Stripe and updates the DB if
  it has changed. Returns {:ok, :updated, new_status} or {:ok, :unchanged}.
  """
  def sync_payment_status(%StripePayment{} = payment) do
    api_key = Application.get_env(:ledgr, :hello_doctor_stripe_api_key)

    with pi_id when not is_nil(pi_id) <- payment.stripe_payment_intent_id,
         {:ok, pi} <-
           Stripe.PaymentIntent.retrieve(pi_id, %{expand: ["latest_charge"]}, api_key: api_key) do
      charge = pi.latest_charge

      stripe_status =
        cond do
          charge && Map.get(charge, :refunded) == true -> "refunded"
          charge && (Map.get(charge, :amount_refunded) || 0) > 0 -> "refunded"
          pi.status == "succeeded" -> "paid"
          pi.status == "canceled" -> "canceled"
          true -> payment.status
        end

      # Also backfill product_name if missing
      product_name =
        if is_nil(payment.product_name) && payment.stripe_session_id do
          fetch_product_name(%{id: payment.stripe_session_id}, api_key)
        end

      updates = %{status: stripe_status}
      updates = if product_name, do: Map.put(updates, :product_name, product_name), else: updates

      if stripe_status != payment.status || product_name do
        payment |> StripePayment.changeset(updates) |> Repo.update()

        Logger.info(
          "[HelloDoctor StripeSync] Payment #{payment.id} updated: status=#{stripe_status}, product=#{product_name || "unchanged"}"
        )

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
        # New payment — check product ID before inserting
        {product_name, line_item_product_ids} = fetch_line_item_info(session, api_key)

        Logger.debug(
          "[HelloDoctor StripeSync] Session #{session.id} product_ids=#{inspect(line_item_product_ids)}"
        )

        if hellodoctor_session?(line_item_product_ids) do
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

          # Try to fetch actual Stripe fee and detect refund status
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
                # link_to_consultation calls ConsultationAccounting.record_payment,
                # which creates the full journal entry (revenue + fee + doctor payout).
                # Do NOT also call create_payment_journal_entry or entries double up.
                link_to_consultation(consultation_id, amount_pesos, session.id)
              else
                # No consultation linked — create a basic GL entry for the revenue.
                create_payment_journal_entry(payment)
              end

              {:ok, payment}

            {:error, changeset} ->
              Logger.warning(
                "[HelloDoctor StripeSync] Failed to insert payment for session #{session.id}: #{inspect(changeset.errors)}"
              )

              {:error, changeset}
          end
        else
          Logger.warning(
            "[HelloDoctor StripeSync] Skipping session #{session.id} — product_ids=#{inspect(line_item_product_ids)} did not match #{inspect(@hellodoctor_product_ids)}"
          )

          {:ok, :skipped}
        end

      _existing ->
        # Already synced
        {:ok, :already_exists}
    end
  end

  defp link_to_consultation(consultation_id, amount_pesos, session_id) do
    case Consultations.get_consultation(consultation_id) do
      nil ->
        :ok

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
        description:
          "Payment from #{payment.customer_name || payment.customer_email || "patient"}",
        payee: payment.customer_name || payment.customer_email
      }

      lines = [
        %{
          account_id: stripe_receivable.id,
          debit_cents: amount_cents,
          credit_cents: 0,
          description: "Stripe payment received"
        },
        %{
          account_id: consultation_revenue.id,
          debit_cents: 0,
          credit_cents: amount_cents,
          description: "Consultation revenue"
        }
      ]

      # Add fee lines if we have the fee
      lines =
        if payment.stripe_fee && payment.stripe_fee > 0 do
          fee_cents = round(payment.stripe_fee * 100)
          processing = Accounting.get_account_by_code!("6000")

          lines ++
            [
              %{
                account_id: processing.id,
                debit_cents: fee_cents,
                credit_cents: 0,
                description: "Stripe processing fee"
              },
              %{
                account_id: stripe_receivable.id,
                debit_cents: 0,
                credit_cents: fee_cents,
                description: "Stripe fee deducted from receivable"
              }
            ]
        else
          lines
        end

      # Add doctor payable lines (85%)
      doctor_payable_account = Accounting.get_account_by_code("2000")

      lines =
        if doctor_payable_account do
          doctor_payout_cents = round(amount_cents * 0.85)

          lines ++
            [
              %{
                account_id: consultation_revenue.id,
                debit_cents: doctor_payout_cents,
                credit_cents: 0,
                description: "Doctor's share (85%)"
              },
              %{
                account_id: doctor_payable_account.id,
                debit_cents: 0,
                credit_cents: doctor_payout_cents,
                description: "Owed to doctor"
              }
            ]
        else
          lines
        end

      Accounting.create_journal_entry_with_lines(entry_attrs, lines)
    rescue
      e ->
        Logger.warning(
          "[HelloDoctor StripeSync] Failed to create journal entry for payment #{payment.id}: #{inspect(e)}"
        )

        :ok
    end
  end

  # Returns {fee_cents_or_nil, status_string} by fetching the payment intent.
  defp fetch_fee_and_status(session, api_key) do
    if session.payment_intent do
      try do
        case Stripe.PaymentIntent.retrieve(session.payment_intent, %{expand: ["latest_charge"]},
               api_key: api_key
             ) do
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

  # Returns {product_name_string_or_nil, [product_id, ...]} for a session.
  # Fetches line items once so both product filtering and name extraction share
  # the same API call.
  defp fetch_line_item_info(session, api_key) do
    try do
      case Stripe.Checkout.Session.retrieve(session.id, %{expand: ["line_items"]},
             api_key: api_key
           ) do
        {:ok, full_session} ->
          # stripity_stripe v3 returns structs — use direct field access, not get_in/2
          items =
            case full_session.line_items do
              %{data: data} when is_list(data) -> data
              data when is_list(data) -> data
              _ -> []
            end

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
              price = Map.get(item, :price) || (is_map(item) && Map.get(item, "price"))

              case price do
                nil ->
                  nil

                _ ->
                  product = Map.get(price, :product) || Map.get(price, "product")

                  case product do
                    pid when is_binary(pid) -> pid
                    %{id: id} -> id
                    _ -> nil
                  end
              end
            end)
            |> Enum.reject(&is_nil/1)

          Logger.debug(
            "[HelloDoctor StripeSync] Session #{session.id} items=#{length(items)} product_ids=#{inspect(product_ids)}"
          )

          {product_name, product_ids}

        {:error, err} ->
          Logger.warning(
            "[HelloDoctor StripeSync] Failed to retrieve line items for session #{session.id}: #{inspect(err)}"
          )

          {nil, []}
      end
    rescue
      e ->
        Logger.warning(
          "[HelloDoctor StripeSync] Exception fetching line items for #{session.id}: #{inspect(e)}"
        )

        {nil, []}
    end
  end

  # Backwards-compatible wrapper used by sync_payment_status/1 for backfilling
  defp fetch_product_name(session, api_key) do
    {product_name, _} = fetch_line_item_info(session, api_key)
    product_name
  end

  defp hellodoctor_session?(product_ids) do
    Enum.any?(product_ids, &(&1 in @hellodoctor_product_ids))
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
