defmodule Ledgr.Domains.HelloDoctor.StripePayouts do
  @moduledoc """
  Records Stripe → bank payouts as journal entries so the Cash Flow report has
  data to work with.

  The HelloDoctor Stripe account is shared with another product line (Retos),
  so each payout's total amount can't be booked wholesale — it'd include cash
  that doesn't belong on HelloDoctor's books. Instead we look at the payout's
  balance_transactions, filter to charges/refunds whose payment_intent appears
  in our consultations or stripe_payments tables, and book only that portion.

  Each payout produces at most one journal entry, keyed by reference
  "Stripe Payout <payout_id>" so re-runs are idempotent.
  """

  require Logger
  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation

  # Bank account that receives Stripe deposits. Could later become configurable
  # if HelloDoctor splits deposits across accounts.
  @bank_account_code "1010"
  @stripe_receivable_code "1200"

  @doc """
  Fetches recent paid payouts from Stripe and books journal entries for the
  consultation-related portion of each. Returns `{:ok, new_count}` or
  `{:error, reason}`.
  """
  def sync_recent_payouts(opts \\ []) do
    api_key = Application.get_env(:ledgr, :hello_doctor_stripe_api_key)

    if is_nil(api_key) do
      Logger.warning("[HelloDoctor StripePayouts] No API key configured")
      {:error, :no_api_key}
    else
      limit = opts[:limit] || 50

      case Stripe.Payout.list(%{limit: limit, status: "paid"}, api_key: api_key) do
        {:ok, %{data: payouts}} ->
          results = Enum.map(payouts, &upsert_payout(&1, api_key))
          new_count = Enum.count(results, &match?({:ok, %JournalEntry{}}, &1))
          already = Enum.count(results, &match?({:ok, :already_recorded}, &1))
          skipped = Enum.count(results, &match?({:ok, :no_consultation_amount}, &1))
          errors = Enum.count(results, &match?({:error, _}, &1))

          Logger.info(
            "[HelloDoctor StripePayouts] Synced #{new_count} new, #{already} already recorded, " <>
              "#{skipped} skipped (no consultation activity), #{errors} errors. " <>
              "Total payouts fetched: #{length(payouts)}"
          )

          {:ok, new_count}

        {:error, err} ->
          Logger.error("[HelloDoctor StripePayouts] Failed to list payouts: #{inspect(err)}")
          {:error, err}
      end
    end
  end

  @doc """
  Public entry point — used by the webhook controller for `payout.paid` events.
  """
  def upsert_payout(payout) do
    api_key = Application.get_env(:ledgr, :hello_doctor_stripe_api_key)
    upsert_payout(payout, api_key)
  end

  def upsert_payout(payout, api_key) do
    reference = "Stripe Payout #{payout.id}"

    if already_recorded?(reference) do
      {:ok, :already_recorded}
    else
      do_create_payout_entry(payout, api_key, reference)
    end
  end

  defp already_recorded?(reference) do
    JournalEntry
    |> where([je], je.reference == ^reference)
    |> Repo.exists?()
  end

  defp do_create_payout_entry(payout, api_key, reference) do
    case fetch_balance_transactions(payout.id, api_key) do
      {:ok, txns} ->
        consultation_net_cents = sum_consultation_net(txns)

        cond do
          consultation_net_cents > 0 ->
            create_journal_entry(payout, consultation_net_cents, reference)

          consultation_net_cents == 0 ->
            Logger.info(
              "[HelloDoctor StripePayouts] Payout #{payout.id} has no consultation activity " <>
                "(likely all Retos) — skipping"
            )

            {:ok, :no_consultation_amount}

          true ->
            # Net negative consultation activity (mostly refunds) — still book it
            # so SR draws down correctly.
            create_journal_entry(payout, consultation_net_cents, reference)
        end

      {:error, err} ->
        Logger.warning(
          "[HelloDoctor StripePayouts] Failed to fetch balance transactions for #{payout.id}: " <>
            inspect(err)
        )

        {:error, err}
    end
  end

  # Stripe paginates balance_transactions; we need them all to sum correctly.
  defp fetch_balance_transactions(payout_id, api_key) do
    do_fetch_btx(payout_id, api_key, nil, [])
  end

  defp do_fetch_btx(payout_id, api_key, starting_after, acc) do
    params =
      %{payout: payout_id, limit: 100, expand: ["data.source"]}
      |> maybe_put(:starting_after, starting_after)

    case Stripe.BalanceTransaction.list(params, api_key: api_key) do
      {:ok, %{data: data, has_more: true}} ->
        last_id = List.last(data).id
        do_fetch_btx(payout_id, api_key, last_id, acc ++ data)

      {:ok, %{data: data}} ->
        {:ok, acc ++ data}

      {:error, err} ->
        {:error, err}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Sums NET amounts (charge minus fees, refund as a negative) for transactions
  # whose underlying charge belongs to a consultation we know about.
  defp sum_consultation_net(txns) do
    Enum.reduce(txns, 0, fn t, acc ->
      cond do
        t.type == "charge" and consultation_charge?(t.source) ->
          acc + (t.net || 0)

        t.type == "refund" and consultation_refund?(t.source) ->
          acc + (t.net || 0)

        true ->
          acc
      end
    end)
  end

  # A charge belongs to a consultation if its payment_intent matches a row in
  # stripe_payments OR consultations.
  defp consultation_charge?(%{payment_intent: pi}) when is_binary(pi), do: pi_known?(pi)
  defp consultation_charge?(_), do: false

  # A refund belongs to a consultation if its payment_intent matches. Stripe's
  # Refund object has `payment_intent` directly — no need to look through .charge.
  defp consultation_refund?(%{payment_intent: pi}) when is_binary(pi), do: pi_known?(pi)
  defp consultation_refund?(_), do: false

  defp pi_known?(pi) do
    stripe_payment_match? =
      StripePayment
      |> where([sp], sp.stripe_payment_intent_id == ^pi)
      |> Repo.exists?()

    if stripe_payment_match? do
      true
    else
      Consultation
      |> where([c], c.stripe_payment_intent_id == ^pi)
      |> Repo.exists?()
    end
  end

  defp create_journal_entry(payout, net_cents, reference) do
    bank = Accounting.get_account_by_code!(@bank_account_code)
    stripe_receivable = Accounting.get_account_by_code!(@stripe_receivable_code)

    arrival_date =
      payout.arrival_date
      |> DateTime.from_unix!()
      |> DateTime.to_date()

    entry_attrs = %{
      date: arrival_date,
      entry_type: "payout",
      reference: reference,
      description:
        "Stripe payout to bank (consultations: $#{format_pesos(net_cents)})",
      payee: "Stripe"
    }

    lines = [
      %{
        account_id: bank.id,
        debit_cents: net_cents,
        credit_cents: 0,
        description: "Bank receipt from Stripe payout"
      },
      %{
        account_id: stripe_receivable.id,
        debit_cents: 0,
        credit_cents: net_cents,
        description: "Reduce Stripe receivable on payout settlement"
      }
    ]

    case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
      {:ok, entry} ->
        Logger.info(
          "[HelloDoctor StripePayouts] Recorded payout #{payout.id} → " <>
            "$#{format_pesos(net_cents)} MXN to bank (consultation portion)"
        )

        {:ok, entry}

      {:error, changeset} ->
        Logger.error(
          "[HelloDoctor StripePayouts] Failed to insert JE for payout #{payout.id}: " <>
            inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  defp format_pesos(cents), do: Float.round(cents / 100.0, 2)
end
