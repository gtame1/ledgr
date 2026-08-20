defmodule Ledgr.Domains.HelloDoctor.CorporateSettlements do
  @moduledoc """
  Records employer payments against a monthly corporate invoice — the
  collection leg for consults an employer is billed for rather than the
  patient.

  Scope: one settlement per (account, month), enforced by a unique index. The
  amount defaults to the **booked** AR for the month (Σ `payment_amount` of
  that account's eligible corporate consults), but the operator can override
  it to match what was actually received.

  Attribution is by the consult's Mexico-City completion month.

  Until 2026-08 a settlement had no table of its own — it *was* a journal
  entry, looked up by a `"Corporate settlement — <slug> <month>"` reference,
  with the amount summed from its lines. Hello Doctor no longer posts to the
  general ledger, so the state lives in `corporate_settlements` now. Rows
  migrated from the old entries keep a `journal_entry_id` pointer.
  """

  require Logger
  import Ecto.Query, warn: false

  alias Ledgr.Domains.HelloDoctor.CorporateSettlements.CorporateSettlement
  alias Ledgr.Repo

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
  `month` (a `"YYYY-MM"` string, Mexico City time), in centavos. This is the
  sum of `payment_amount` over the same eligible corporate consults
  `ConsultationAccounting.record_corporate_payment/1` posts AR for, so it's the
  natural default for what the employer owes that month.
  """
  def booked_ar_cents(account_id, month) when is_binary(account_id) and is_binary(month) do
    sql = """
    SELECT COALESCE(SUM(c.payment_amount), 0)
    FROM consultations c
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

    %{rows: [[pesos]]} = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [account_id, month])
    round(to_f(pesos) * 100)
  end

  def booked_ar_cents(_, _), do: 0

  @doc """
  The settlement for (slug, month), or `nil` if the invoice hasn't been
  settled yet.
  """
  def settlement_for(slug, month) when is_binary(slug) and is_binary(month) do
    Repo.get_by(CorporateSettlement, account_slug: slug, month: month)
  end

  def settlement_for(_, _), do: nil

  @doc "Whether (slug, month) already has a settlement recorded."
  def settled?(slug, month), do: not is_nil(settlement_for(slug, month))

  @doc "Amount settled, in centavos."
  def settlement_amount_cents(%CorporateSettlement{amount_cents: cents}) when is_integer(cents),
    do: cents

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
    name = attrs[:account_name] || slug

    attrs = %{
      account_slug: slug,
      month: month,
      amount_cents: amount_cents,
      deposit_code: normalize_deposit(attrs[:deposit_code]),
      settled_on: attrs[:date] || Ledgr.Domains.HelloDoctor.today(),
      account_name: name
    }

    %CorporateSettlement{}
    |> CorporateSettlement.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, settlement} ->
        Logger.info(
          "[HelloDoctor] Recorded corporate settlement ##{settlement.id} for #{slug} #{month}: " <>
            "$#{amount_cents / 100} MXN → #{settlement.deposit_code}"
        )

        {:ok, settlement}

      {:error, changeset} ->
        Logger.error(
          "[HelloDoctor] Failed to record corporate settlement for #{slug} #{month}: #{inspect(changeset)}"
        )

        {:error, changeset}
    end
  end

  @doc """
  The reference the pre-2026-08 journal entries used. Kept so the backfill
  migration and any historical lookup agree on the key.
  """
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
