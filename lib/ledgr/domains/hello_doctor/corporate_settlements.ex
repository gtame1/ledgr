defmodule Ledgr.Domains.HelloDoctor.CorporateSettlements do
  @moduledoc """
  Records employer payments against a monthly corporate invoice — the
  collection leg that clears the receivable posted when a corporate consult is
  delivered.

  A corporate consult recognizes revenue against Accounts Receivable
  (`ConsultationAccounting.record_corporate_payment/1`:
  `Dr 1100 / Cr 4000`). When the employer settles that month's invoice, this
  posts the cash movement:

      DEBIT  1010 Bank - MXN            $amount   (money in)
      CREDIT 1100 Accounts Receivable   $amount   (receivable cleared)

  Scope: one settlement per (account, month), reference-keyed and idempotent —
  no denormalized table (same style as the comp-accrual entries). The amount
  defaults to the **booked** AR for the month — the same per-consult revenue
  rule `record_corporate_payment/1` applies, so it is exactly what that
  function debited to 1100 — but the operator can override it to match what
  was actually received: a short-pay simply leaves the residual sitting in
  1100, which is correct.

  Attribution is by the consult's Mexico-City completion month, matching the
  date `record_corporate_payment/1` stamps on the AR entry, so the two line up.
  """

  require Logger
  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry

  @accounts_receivable_code "1100"
  @default_deposit_code "1010"

  @doc """
  Cash/bank accounts an employer payment can be deposited into, as
  `{code, label}` — for the deposit-account picker on the invoice page.
  """
  def deposit_accounts do
    [
      {"1010", "Bank - MXN"},
      {"1000", "Cash"},
      {"1020", "Bank - USD"}
    ]
  end

  defp deposit_codes, do: Enum.map(deposit_accounts(), &elem(&1, 0))

  @doc """
  Booked Accounts-Receivable for a corporate account's consults completed in
  `month` (a `"YYYY-MM"` string, Mexico City time), in centavos. This sums the
  same eligible corporate consults `record_corporate_payment/1` posts AR for,
  under the same per-consult revenue rule, so it's the natural default for what
  the employer owes that month.

  The revenue rule mirrors `ConsultationAccounting.corporate_revenue_cents/1`:
  the amount stamped on the consultation, falling back to the employer's
  contracted `consultation_rate_mxn` when there isn't one. Note the fallback
  fires on **zero as well as NULL** — a corporate consult booked at 0 still
  debits 1100 the full contracted rate, so summing `payment_amount` alone would
  understate the receivable and settling at that default would strand a
  residual in 1100 that looks like a short-pay but isn't. Same alignment the
  `analytics.fct_consultation.gross_mxn` column carries (`01146b9`).

  Rounding is per consult, matching how the GL posted each entry, rather than
  applied once to the sum.
  """
  def booked_ar_cents(account_id, month) when is_binary(account_id) and is_binary(month) do
    sql = """
    SELECT COALESCE(SUM(ROUND((
             CASE
               WHEN COALESCE(c.payment_amount, 0) > 0 THEN c.payment_amount
               ELSE COALESCE(ca.consultation_rate_mxn, 0)
             END
           )::numeric * 100)), 0)
    FROM consultations c
    LEFT JOIN corporate_accounts ca ON ca.id = c.corporate_account_id
    WHERE c.corporate_account_id = $1
      AND COALESCE(c.payment_source, 'stripe') = 'corporate'
      AND COALESCE(c.payment_status, '') IN ('paid', 'confirmed')
      AND COALESCE(c.status, '') NOT IN ('cancelled', 'consultation_failed')
      AND to_char(
            date_trunc(
              'month',
              (c.completed_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')
            ),
            'YYYY-MM'
          ) = $2
    """

    %{rows: [[cents]]} = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [account_id, month])
    round(to_f(cents))
  end

  def booked_ar_cents(_, _), do: 0

  @doc """
  The settlement journal entry for (slug, month) with its lines preloaded, or
  `nil` if the invoice hasn't been settled yet.
  """
  def settlement_for(slug, month) when is_binary(slug) and is_binary(month) do
    ref = reference(slug, month)

    JournalEntry
    |> where([je], je.reference == ^ref)
    |> preload(:journal_lines)
    |> Repo.one()
  end

  def settlement_for(_, _), do: nil

  @doc "Whether (slug, month) already has a settlement recorded."
  def settled?(slug, month), do: not is_nil(settlement_for(slug, month))

  @doc "Amount settled (debit side), in centavos, for a settlement entry."
  def settlement_amount_cents(%JournalEntry{journal_lines: lines}) when is_list(lines),
    do: Enum.reduce(lines, 0, fn l, acc -> acc + (l.debit_cents || 0) end)

  def settlement_amount_cents(_), do: 0

  @doc """
  Records an employer payment against the (slug, month) invoice.

  `attrs`:
    * `:amount_cents` — integer > 0 (the amount received)
    * `:date` — `Date` the payment landed
    * `:deposit_code` — account code money landed in (defaults to 1010 Bank-MXN)
    * `:account_name` — company name, for the entry description/payee

  Posts `Dr <deposit> / Cr 1100`. Idempotent per (slug, month): returns
  `{:error, :already_settled}` if a settlement already exists. Returns
  `{:error, :invalid_amount}` for a non-positive amount.
  """
  def record_settlement(slug, month, attrs) when is_binary(slug) and is_binary(month) do
    amount_cents = attrs[:amount_cents] || 0

    cond do
      settled?(slug, month) -> {:error, :already_settled}
      not (is_integer(amount_cents) and amount_cents > 0) -> {:error, :invalid_amount}
      true -> do_record_settlement(slug, month, attrs, amount_cents)
    end
  end

  defp do_record_settlement(slug, month, attrs, amount_cents) do
    deposit_code = normalize_deposit(attrs[:deposit_code])
    name = attrs[:account_name] || slug
    date = attrs[:date] || Ledgr.Domains.HelloDoctor.today()

    accounts_receivable = Accounting.get_account_by_code!(@accounts_receivable_code)
    deposit = Accounting.get_account_by_code!(deposit_code)

    entry_attrs = %{
      date: date,
      entry_type: "corporate_settlement",
      reference: reference(slug, month),
      description: "Corporate settlement — #{name} — #{month}",
      payee: name
    }

    lines = [
      %{
        account_id: deposit.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Payment received from #{name} (#{month})"
      },
      %{
        account_id: accounts_receivable.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Clearing corporate receivable — #{name} (#{month})"
      }
    ]

    case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
      {:ok, entry} ->
        Logger.info(
          "[HelloDoctor] Recorded corporate settlement ##{entry.id} for #{slug} #{month}: $#{amount_cents / 100} MXN → #{deposit_code}"
        )

        {:ok, entry}

      {:error, changeset} ->
        Logger.error(
          "[HelloDoctor] Failed to record corporate settlement for #{slug} #{month}: #{inspect(changeset)}"
        )

        {:error, changeset}
    end
  end

  @doc "Stable idempotency reference for a (slug, month) settlement."
  def reference(slug, month), do: "Corporate settlement — #{slug} #{month}"

  defp normalize_deposit(code) when is_binary(code) do
    if code in deposit_codes(), do: code, else: @default_deposit_code
  end

  defp normalize_deposit(_), do: @default_deposit_code

  defp to_f(nil), do: 0.0
  defp to_f(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_f(n) when is_integer(n), do: n * 1.0
  defp to_f(n) when is_float(n), do: n
end
