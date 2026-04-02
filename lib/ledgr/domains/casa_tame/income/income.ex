defmodule Ledgr.Domains.CasaTame.Income do
  @moduledoc """
  Manages personal income entries for Casa Tame with dual-currency support.
  """

  import Ecto.Query, warn: false
  alias Ledgr.Repo

  alias Ledgr.Domains.CasaTame.Income.IncomeEntry
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry

  @default_revenue_code "4050"

  def list_income_entries(opts \\ []) do
    query =
      from e in IncomeEntry,
        preload: [:income_category, :deposit_account],
        order_by: [desc: e.date, desc: e.inserted_at]

    query
    |> maybe_filter(:currency, opts[:currency])
    |> maybe_filter(:income_category_id, opts[:category_id])
    |> maybe_filter_date(:date_from, opts[:date_from])
    |> maybe_filter_date(:date_to, opts[:date_to])
    |> Repo.all()
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, _field, ""), do: query
  defp maybe_filter(query, :currency, val), do: from(e in query, where: e.currency == ^val)
  defp maybe_filter(query, :income_category_id, val), do: from(e in query, where: e.income_category_id == ^val)

  defp maybe_filter_date(query, _dir, nil), do: query
  defp maybe_filter_date(query, _dir, ""), do: query
  defp maybe_filter_date(query, :date_from, d) do
    date = if is_binary(d), do: Date.from_iso8601!(d), else: d
    from e in query, where: e.date >= ^date
  end
  defp maybe_filter_date(query, :date_to, d) do
    date = if is_binary(d), do: Date.from_iso8601!(d), else: d
    from e in query, where: e.date <= ^date
  end

  def get_income_entry!(id) do
    IncomeEntry
    |> Repo.get!(id)
    |> Repo.preload([:income_category, :deposit_account])
  end

  def change_income_entry(%IncomeEntry{} = entry, attrs \\ %{}) do
    IncomeEntry.changeset(entry, attrs)
  end

  def create_income_entry_with_journal(attrs) do
    Repo.transaction(fn ->
      with {:ok, entry} <-
             %IncomeEntry{}
             |> IncomeEntry.changeset(attrs)
             |> Repo.insert(),
           {:ok, _je} <- record_income_journal(entry) do
        entry
      else
        {:error, changeset = %Ecto.Changeset{}} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_income_entry_with_journal(%IncomeEntry{} = entry, attrs) do
    Repo.transaction(fn ->
      with {:ok, updated} <-
             entry
             |> IncomeEntry.changeset(attrs)
             |> Repo.update(),
           {:ok, _je} <- update_income_journal(updated) do
        updated
      else
        {:error, changeset = %Ecto.Changeset{}} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_income_entry(%IncomeEntry{} = entry) do
    Repo.transaction(fn ->
      reference = "Income ##{entry.id}"
      je = from(j in JournalEntry, where: j.reference == ^reference) |> Repo.one()
      if je, do: Repo.delete!(je)
      Repo.delete!(entry)
    end)
  end

  @doc "Returns income totals grouped by income category name and currency."
  def totals_by_category_and_currency(start_date, end_date) do
    from(e in IncomeEntry,
      where: e.date >= ^start_date and e.date <= ^end_date,
      left_join: c in assoc(e, :income_category),
      group_by: [e.currency, c.name],
      select: %{
        currency: e.currency,
        category_name: c.name,
        total_cents: coalesce(sum(e.amount_cents), 0)
      },
      order_by: [desc: coalesce(sum(e.amount_cents), 0)]
    )
    |> Repo.all()
  end

  def total_by_currency(start_date, end_date) do
    results =
      from(e in IncomeEntry,
        where: e.date >= ^start_date and e.date <= ^end_date,
        group_by: e.currency,
        select: {e.currency, coalesce(sum(e.amount_cents), 0)}
      )
      |> Repo.all()
      |> Map.new()

    %{usd: Map.get(results, "USD", 0), mxn: Map.get(results, "MXN", 0)}
  end

  # ── Journal Entry Helpers ──────────────────────────────────────

  defp record_income_journal(%IncomeEntry{} = entry) do
    revenue_account = resolve_revenue_account(entry)

    lines = [
      %{
        account_id: entry.deposit_account_id,
        debit_cents: entry.amount_cents,
        credit_cents: 0,
        description: "Income deposit: #{entry.description}"
      },
      %{
        account_id: revenue_account.id,
        debit_cents: 0,
        credit_cents: entry.amount_cents,
        description: "Revenue: #{entry.description}"
      }
    ]

    Accounting.create_journal_entry_with_lines(
      %{
        date: entry.date,
        entry_type: "income",
        reference: "Income ##{entry.id}",
        description: entry.description
      },
      lines
    )
  end

  defp update_income_journal(%IncomeEntry{} = entry) do
    reference = "Income ##{entry.id}"
    je = from(j in JournalEntry, where: j.reference == ^reference) |> Repo.one()
    revenue_account = resolve_revenue_account(entry)

    lines = [
      %{
        account_id: entry.deposit_account_id,
        debit_cents: entry.amount_cents,
        credit_cents: 0,
        description: "Income deposit: #{entry.description}"
      },
      %{
        account_id: revenue_account.id,
        debit_cents: 0,
        credit_cents: entry.amount_cents,
        description: "Revenue: #{entry.description}"
      }
    ]

    if je do
      Accounting.update_journal_entry_with_lines(
        je,
        %{date: entry.date, description: entry.description},
        lines
      )
    else
      record_income_journal(entry)
    end
  end

  # Maps income category names to revenue account codes.
  # Currency-aware: Wages maps to USD or MXN wages based on the entry's currency.
  @category_to_revenue %{
    "Wages & Salary"         => %{"USD" => "4000", "MXN" => "4010"},
    "Freelance"              => %{"USD" => "4020", "MXN" => "4020"},
    "Investments & Dividends"=> %{"USD" => "4030", "MXN" => "4030"},
    "Rental Income"          => %{"USD" => "4040", "MXN" => "4040"},
    "Side Income"            => %{"USD" => "4020", "MXN" => "4020"}
  }

  defp resolve_revenue_account(%IncomeEntry{} = entry) do
    entry = Ledgr.Repo.preload(entry, :income_category)
    currency = entry.currency || "MXN"

    code =
      case entry.income_category do
        nil ->
          @default_revenue_code

        cat ->
          case Map.get(@category_to_revenue, cat.name) do
            nil -> @default_revenue_code
            currency_map -> Map.get(currency_map, currency, @default_revenue_code)
          end
      end

    Accounting.get_account_by_code!(code)
  end
end
