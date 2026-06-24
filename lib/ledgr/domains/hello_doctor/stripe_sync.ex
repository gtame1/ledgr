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
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment
  alias Ledgr.Domains.HelloDoctor.Consultations
  alias Ledgr.Domains.HelloDoctor.StripeRefunds
  alias Ledgr.Core.Accounting

  # Stripe product IDs that belong to HelloDoctor. The bot's payment links
  # are bound to prod_UM2NWeVCm0EJEG (created earlier, now archived in the
  # Stripe dashboard but still active for existing payment links). The "new"
  # prod_UHpGzvMsR5pRZb is the visible canonical product but not yet used by
  # the bot. Keep both so we capture payments either way.
  # Override at runtime by setting :hello_doctor_stripe_product_ids in config.
  @default_hellodoctor_product_ids [
    "prod_UM2NWeVCm0EJEG",
    "prod_UHpGzvMsR5pRZb"
  ]

  defp hellodoctor_product_ids do
    Application.get_env(:ledgr, :hello_doctor_stripe_product_ids) ||
      @default_hellodoctor_product_ids
  end

  @doc """
  Fetches recent completed checkout sessions from Stripe and upserts them
  into the local stripe_payments table. Returns {:ok, count_synced}.

  Only sessions that contain a HelloDoctor product (matched by product ID) are
  stored — everything else from the shared Stripe account is silently skipped.
  """
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
  Re-fetches Stripe fees for `stripe_payments` rows where `stripe_fee` is
  NULL. Stripe doesn't always have the balance_transaction populated on a
  charge at `checkout.session.completed` time, so webhook-inserted rows
  often land with a nil fee. Calling this later (once funds have settled
  on Stripe's side) backfills them by retrieving the PaymentIntent's
  latest_charge → balance_transaction → fee.

  Idempotent — only touches rows whose fee is still NULL and whose
  payment_intent we can look up.

  Returns `%{updated: N, no_fee_yet: N, no_pi: N, errors: N}`.
  """
  def backfill_missing_fees do
    import Ecto.Query, warn: false

    api_key = Application.get_env(:ledgr, :hello_doctor_stripe_api_key)

    if is_nil(api_key) do
      Logger.warning("[HelloDoctor StripeSync] No API key configured for fee backfill")
      {:error, :no_api_key}
    else
      payments =
        StripePayment
        |> where([p], is_nil(p.stripe_fee))
        |> Repo.all()

      Logger.info(
        "[HelloDoctor StripeSync] Backfilling fees: #{length(payments)} candidate row(s)"
      )

      result =
        Enum.reduce(payments, %{updated: 0, no_fee_yet: 0, no_pi: 0, errors: 0}, fn payment, acc ->
          cond do
            is_nil(payment.stripe_payment_intent_id) ->
              %{acc | no_pi: acc.no_pi + 1}

            true ->
              case fetch_fee_for_payment_intent(payment.stripe_payment_intent_id, api_key) do
                {:ok, fee_cents} when is_integer(fee_cents) and fee_cents > 0 ->
                  fee_pesos = fee_cents / 100.0

                  case payment
                       |> StripePayment.changeset(%{stripe_fee: fee_pesos})
                       |> Repo.update() do
                    {:ok, _} ->
                      Logger.info(
                        "[HelloDoctor StripeSync] Backfilled fee for payment #{payment.id} " <>
                          "(session #{payment.stripe_session_id}): $#{fee_pesos} MXN"
                      )

                      %{acc | updated: acc.updated + 1}

                    {:error, changeset} ->
                      Logger.error(
                        "[HelloDoctor StripeSync] Failed to save fee for payment #{payment.id}: " <>
                          "#{inspect(changeset.errors)}"
                      )

                      %{acc | errors: acc.errors + 1}
                  end

                {:ok, _} ->
                  # Stripe returned but the balance_transaction isn't ready yet.
                  %{acc | no_fee_yet: acc.no_fee_yet + 1}

                {:error, _} ->
                  %{acc | errors: acc.errors + 1}
              end
          end
        end)

      Logger.info("[HelloDoctor StripeSync] Fee backfill complete: #{inspect(result)}")
      {:ok, result}
    end
  end

  # Given a payment_intent id, retrieve the latest_charge and its
  # balance_transaction, returning {:ok, fee_cents} on success or {:error, ...}
  # on Stripe failure. fee_cents is nil if the BT isn't populated yet.
  defp fetch_fee_for_payment_intent(pi_id, api_key) do
    try do
      case Stripe.PaymentIntent.retrieve(pi_id, %{expand: ["latest_charge"]}, api_key: api_key) do
        {:ok, pi} ->
          charge = pi.latest_charge
          {:ok, fetch_charge_fee(charge, api_key)}

        {:error, reason} ->
          Logger.warning(
            "[HelloDoctor StripeSync] Stripe error fetching PI #{pi_id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    rescue
      e ->
        Logger.warning(
          "[HelloDoctor StripeSync] Exception fetching PI #{pi_id}: #{inspect(e)}"
        )

        {:error, e}
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
      original_cents = round(payment.amount * 100)
      amount_refunded_cents = (charge && Map.get(charge, :amount_refunded)) || 0
      amount_refunded_pesos = amount_refunded_cents / 100.0

      stripe_status =
        cond do
          charge && Map.get(charge, :refunded) == true ->
            "refunded"

          amount_refunded_cents > 0 && amount_refunded_cents >= original_cents ->
            "refunded"

          amount_refunded_cents > 0 ->
            "partially_refunded"

          pi.status == "succeeded" ->
            "paid"

          pi.status == "canceled" ->
            "canceled"

          true ->
            payment.status
        end

      # Also backfill product_name if missing
      product_name =
        if is_nil(payment.product_name) && payment.stripe_session_id do
          fetch_product_name(%{id: payment.stripe_session_id}, api_key)
        end

      changed_refund? = amount_refunded_pesos != (payment.amount_refunded || 0.0)
      changed_status? = stripe_status != payment.status

      updates = %{status: stripe_status, amount_refunded: amount_refunded_pesos}
      updates = if product_name, do: Map.put(updates, :product_name, product_name), else: updates

      if changed_status? || changed_refund? || product_name do
        payment |> StripePayment.changeset(updates) |> Repo.update()

        Logger.info(
          "[HelloDoctor StripeSync] Payment #{payment.id} updated: status=#{stripe_status}, refunded=$#{amount_refunded_pesos}, product=#{product_name || "unchanged"}"
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
          {discount_code, discount_amount} = fetch_discount_info(session, api_key)
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

          # Single Stripe API round trip — yields fee, refund state, status,
          # and the *actual* charge time.
          charge_info = fetch_charge_info(session, api_key)
          fee_pesos = if charge_info.fee_cents, do: charge_info.fee_cents / 100.0, else: nil
          amount_refunded_pesos = charge_info.amount_refunded_cents / 100.0

          attrs = %{
            stripe_session_id: session.id,
            stripe_payment_intent_id: session.payment_intent,
            amount: amount_pesos,
            amount_refunded: amount_refunded_pesos,
            currency: session.currency || "mxn",
            status: charge_info.status,
            customer_email: customer_email,
            customer_name: customer_name,
            consultation_id: consultation_id,
            stripe_fee: fee_pesos,
            product_name: product_name,
            discount_code: discount_code,
            discount_amount: discount_amount,
            paid_at: charge_info.paid_at_naive
          }

          # Insert the payment AND its journal entry inside one transaction —
          # avoids orphaning a payment row if the GL side fails. If anything
          # rolls back, both sides are gone and the next sync/webhook will
          # cleanly retry.
          Repo.transaction(fn ->
            case %StripePayment{}
                 |> StripePayment.changeset(attrs)
                 |> Repo.insert() do
              {:ok, payment} ->
                je_result =
                  if consultation_id do
                    link_to_consultation(
                      consultation_id,
                      amount_pesos,
                      session.id,
                      charge_info.fee_cents
                    )
                  else
                    create_payment_journal_entry(payment)
                  end

                case je_result do
                  {:ok, _} -> payment
                  {:error, reason} -> Repo.rollback(reason)
                  :ok -> payment
                  _ -> payment
                end

              {:error, changeset} ->
                Logger.warning(
                  "[HelloDoctor StripeSync] Failed to insert payment for session #{session.id}: #{inspect(changeset.errors)}"
                )

                Repo.rollback(changeset)
            end
          end)
        else
          Logger.warning(
            "[HelloDoctor StripeSync] Skipping session #{session.id} — product_ids=#{inspect(line_item_product_ids)} did not match #{inspect(hellodoctor_product_ids())}"
          )

          {:ok, :skipped}
        end

      _existing ->
        # Already synced
        {:ok, :already_exists}
    end
  end

  defp link_to_consultation(consultation_id, amount_pesos, session_id, fee_cents) do
    case Consultations.get_consultation(consultation_id) do
      nil ->
        {:ok, :no_consultation}

      consultation ->
        Consultations.record_stripe_payment(consultation, %{
          payment_amount: amount_pesos,
          stripe_session_id: session_id,
          stripe_fee_cents: fee_cents
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

      # Add doctor payable lines (flat $100 MXN per paid consultation)
      doctor_payable_account = Accounting.get_account_by_code("2000")

      lines =
        if doctor_payable_account do
          doctor_payout_cents = ConsultationAccounting.doctor_share_cents()

          lines ++
            [
              %{
                account_id: consultation_revenue.id,
                debit_cents: doctor_payout_cents,
                credit_cents: 0,
                description: "Doctor's share"
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

  # Returns a charge_info map by fetching the payment intent's latest charge.
  # Centralises every field that depends on the charge so we only hit the
  # Stripe API once per webhook (vs. the old code which re-fetched the fee
  # later in ConsultationAccounting.record_payment).
  #
  #   %{
  #     fee_cents: integer | nil,           # actual Stripe processing fee
  #     amount_refunded_cents: integer,     # 0 for non-refunded payments
  #     status: "paid" | "refunded" | "partially_refunded" | "canceled",
  #     paid_at_naive: NaiveDateTime.t      # actual charge time, not session create
  #   }
  defp fetch_charge_info(session, api_key) do
    fallback = %{
      fee_cents: nil,
      amount_refunded_cents: 0,
      status: "paid",
      paid_at_naive: session_created_naive(session)
    }

    if session.payment_intent do
      try do
        case Stripe.PaymentIntent.retrieve(session.payment_intent, %{expand: ["latest_charge"]},
               api_key: api_key
             ) do
          {:ok, pi} ->
            charge = pi.latest_charge
            amount_refunded = (charge && Map.get(charge, :amount_refunded)) || 0
            session_amount = session.amount_total || 0

            status =
              cond do
                charge && Map.get(charge, :refunded) == true ->
                  "refunded"

                amount_refunded > 0 && amount_refunded >= session_amount ->
                  "refunded"

                amount_refunded > 0 ->
                  "partially_refunded"

                pi.status == "succeeded" ->
                  "paid"

                pi.status == "canceled" ->
                  "canceled"

                true ->
                  "paid"
              end

            fee = fetch_charge_fee(charge, api_key)
            paid_at = charge_paid_at(charge) || fallback.paid_at_naive

            %{
              fee_cents: fee,
              amount_refunded_cents: amount_refunded,
              status: status,
              paid_at_naive: paid_at
            }

          _ ->
            fallback
        end
      rescue
        _ -> fallback
      end
    else
      fallback
    end
  end

  defp fetch_charge_fee(nil, _api_key), do: nil

  defp fetch_charge_fee(charge, api_key) do
    bt_id = Map.get(charge, :balance_transaction)
    bt_id = if is_binary(bt_id), do: bt_id, else: bt_id && Map.get(bt_id, :id)

    if bt_id do
      case Stripe.BalanceTransaction.retrieve(bt_id, %{}, api_key: api_key) do
        {:ok, bt} -> bt.fee
        _ -> nil
      end
    end
  end

  defp charge_paid_at(nil), do: nil

  defp charge_paid_at(charge) do
    case Map.get(charge, :created) do
      ts when is_integer(ts) ->
        ts
        |> DateTime.from_unix!()
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)

      _ ->
        nil
    end
  end

  defp session_created_naive(session) do
    DateTime.from_unix!(session.created)
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
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

  # Returns `{discount_code, discount_amount_pesos}` for a session, or
  # `{nil, nil}` when no promo/coupon was applied. The session is retrieved
  # with `discounts.promotion_code` expanded so we get the human code
  # ("SALUD26"), falling back to the coupon name/id if a coupon was applied
  # directly without a promotion code. `amount_discount` is on the session
  # by default (no expansion needed).
  defp fetch_discount_info(session, api_key) do
    try do
      case Stripe.Checkout.Session.retrieve(session.id, %{expand: ["discounts.promotion_code"]},
             api_key: api_key
           ) do
        {:ok, full_session} -> extract_discount(full_session)
        {:error, _} -> {nil, nil}
      end
    rescue
      _ -> {nil, nil}
    end
  end

  defp extract_discount(session) do
    amount =
      case Map.get(session, :total_details) do
        %{amount_discount: cents} when is_integer(cents) and cents > 0 -> cents / 100.0
        _ -> nil
      end

    code =
      (Map.get(session, :discounts) || [])
      |> Enum.find_value(fn d ->
        case Map.get(d, :promotion_code) do
          %{} = pc -> Map.get(pc, :code)
          code when is_binary(code) -> code
          _ -> coupon_label(Map.get(d, :coupon))
        end
      end)

    {code, amount}
  end

  defp coupon_label(%{} = coupon), do: Map.get(coupon, :name) || Map.get(coupon, :id)
  defp coupon_label(id) when is_binary(id), do: id
  defp coupon_label(_), do: nil

  @doc """
  Backfills `discount_code` / `discount_amount` on existing `stripe_payments`
  rows that were synced before discount capture existed (where both are
  NULL). Re-reads each row's Checkout Session from Stripe. Idempotent, but
  re-checks full-price rows each run (a NULL code is indistinguishable from
  "not yet checked") — fine at our volume. Returns
  `%{updated: N, no_discount: N, errors: N}`.
  """
  def backfill_discounts do
    import Ecto.Query, warn: false

    api_key = Application.get_env(:ledgr, :hello_doctor_stripe_api_key)

    if is_nil(api_key) do
      Logger.warning("[HelloDoctor StripeSync] No API key configured for discount backfill")
      {:error, :no_api_key}
    else
      payments =
        StripePayment
        |> where([p], is_nil(p.discount_code) and is_nil(p.discount_amount))
        |> where([p], not is_nil(p.stripe_session_id))
        |> Repo.all()

      result =
        Enum.reduce(payments, %{updated: 0, no_discount: 0, errors: 0}, fn payment, acc ->
          case fetch_discount_info(%{id: payment.stripe_session_id}, api_key) do
            {nil, nil} ->
              %{acc | no_discount: acc.no_discount + 1}

            {code, amount} ->
              case payment
                   |> StripePayment.changeset(%{discount_code: code, discount_amount: amount})
                   |> Repo.update() do
                {:ok, _} -> %{acc | updated: acc.updated + 1}
                {:error, _} -> %{acc | errors: acc.errors + 1}
              end
          end
        end)

      Logger.info("[HelloDoctor StripeSync] Discount backfill complete: #{inspect(result)}")
      {:ok, result}
    end
  end

  defp hellodoctor_session?(product_ids) do
    allowlist = hellodoctor_product_ids()
    Enum.any?(product_ids, &(&1 in allowlist))
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
