defmodule LedgrWeb.AccountTransactionController do
  use LedgrWeb, :controller

  alias Ledgr.Core.Accounting
  import Ecto.Query

  def index(conn, params) do
    accounts = Accounting.list_asset_liability_accounts()
    account_id = params["account_id"]
    filters = build_filters(params, account_id)
    date_from = parse_date(filters.date_from)
    date_to = parse_date(filters.date_to)

    {selected_account, transactions, running_balance} =
      case parse_account_id(account_id) do
        nil ->
          {nil, [], 0}

        account_id_int ->
          account = Accounting.get_account!(account_id_int)

          journal_lines =
            Accounting.list_journal_lines_by_account(account_id_int,
              date_from: date_from,
              date_to: date_to
            )

          {transactions_with_balance, running_balance} =
            compute_running_balances(journal_lines, account)

          {account, transactions_with_balance, running_balance}
      end

    # Load reconciliation checkpoints (line-less journal entries) and merge
    # with regular transactions into a single sorted display list.
    checkpoints =
      case selected_account do
        nil -> []
        account -> load_reconciliation_checkpoints(account)
      end

    all_items = merge_with_checkpoints(transactions, checkpoints)
    expense_info = build_expense_info(transactions, conn.assigns[:current_domain])
    {earliest_date, latest_date} = Accounting.journal_entry_date_range()

    render(conn, :index,
      accounts: accounts,
      selected_account: selected_account,
      all_items: all_items,
      running_balance: running_balance,
      filters: filters,
      earliest_date: earliest_date,
      latest_date: latest_date,
      expense_info: expense_info
    )
  end

  def reconcile(conn, %{"account_id" => account_id}) do
    account = Accounting.get_account!(account_id)

    entry_attrs = %{
      date: Date.utc_today(),
      description: "Reconciled",
      entry_type: "reconciliation",
      reference: "Reconcile #{account.code}"
    }

    # Pass empty lines — validate_balanced allows 0==0, and validate_non_zero
    # only fires on actual line changesets, so an empty list passes cleanly.
    lines = []

    case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Account marked as reconciled.")
        |> redirect(to: dp(conn, "/account-transactions?account_id=#{account_id}"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not record reconciliation.")
        |> redirect(to: dp(conn, "/account-transactions?account_id=#{account_id}"))
    end
  end

  # ── Private ────────────────────────────────────────────────

  defp build_expense_info([], _domain), do: %{}

  defp build_expense_info(transactions, domain) do
    # Extract journal entry IDs that have references like "Expense #123"
    je_refs =
      transactions
      |> Enum.map(& &1.line.journal_entry)
      |> Enum.uniq_by(& &1.id)
      |> Enum.filter(&(&1.reference && String.starts_with?(&1.reference, "Expense #")))

    expense_ids =
      Enum.flat_map(je_refs, fn je ->
        case Integer.parse(String.replace_prefix(je.reference, "Expense #", "")) do
          {id, ""} -> [id]
          _ -> []
        end
      end)

    if Enum.empty?(expense_ids) do
      %{}
    else
      alias Ledgr.Core.Accounting.Account

      expense_schema = Ledgr.Core.Expenses.Expense

      expenses =
        Ledgr.Repo.all(
          from e in expense_schema,
            where: e.id in ^expense_ids,
            join: a in Account,
            on: a.id == e.expense_account_id,
            preload: [expense_account: a]
        )

      expense_map = Map.new(expenses, &{&1.id, &1})

      Enum.reduce(je_refs, %{}, fn je, acc ->
        case Integer.parse(String.replace_prefix(je.reference, "Expense #", "")) do
          {expense_id, ""} ->
            case Map.get(expense_map, expense_id) do
              nil -> acc
              expense ->
                Map.put(acc, je.id, %{
                  description: expense.description,
                  category: expense.expense_account && expense.expense_account.name
                })
            end
          _ -> acc
        end
      end)
    end
  end

  defp compute_running_balances(journal_lines, account) do
    oldest_first = Enum.reverse(journal_lines)

    {running_balance, newest_first} =
      Enum.reduce(oldest_first, {0, []}, fn line, {current_balance, acc} ->
        new_balance =
          if account.normal_balance == "debit" do
            current_balance + line.debit_cents - line.credit_cents
          else
            current_balance + line.credit_cents - line.debit_cents
          end

        row = %{line: line, balance: new_balance}
        {new_balance, [row | acc]}
      end)

    {newest_first, running_balance}
  end

  # Load reconciliation journal entries (no lines) keyed to this account's code.
  defp load_reconciliation_checkpoints(account) do
    alias Ledgr.Core.Accounting.JournalEntry

    Ledgr.Repo.all(
      from je in JournalEntry,
        where:
          je.entry_type == "reconciliation" and
            je.reference == ^"Reconcile #{account.code}",
        order_by: [desc: je.date, desc: je.inserted_at]
    )
  end

  # Merge regular transactions and reconciliation checkpoints into a single
  # newest-first list.  On the same date, transactions appear before the
  # checkpoint divider (priority 1 > 0 in descending sort).
  defp merge_with_checkpoints(transactions, checkpoints) do
    tx_items =
      Enum.map(transactions, fn tx ->
        %{kind: :tx, date: tx.line.journal_entry.date, data: tx}
      end)

    cp_items =
      Enum.map(checkpoints, fn entry ->
        %{kind: :checkpoint, date: entry.date, data: entry}
      end)

    (tx_items ++ cp_items)
    |> Enum.sort_by(
      fn
        %{kind: :tx, date: date} -> {Date.to_gregorian_days(date), 1}
        %{kind: :checkpoint, date: date} -> {Date.to_gregorian_days(date), 0}
      end,
      :desc
    )
  end

  defp build_filters(params, account_id) do
    if params["all_dates"] == "true" do
      {earliest, latest} = Accounting.journal_entry_date_range()
      %{
        account_id: account_id || "",
        date_from: if(earliest, do: Date.to_iso8601(earliest), else: ""),
        date_to: if(latest, do: Date.to_iso8601(latest), else: "")
      }
    else
      %{
        account_id: account_id || "",
        date_from: params["date_from"] || "",
        date_to: params["date_to"] || ""
      }
    end
  end

  defp parse_account_id(nil), do: nil
  defp parse_account_id(""), do: nil
  defp parse_account_id(id_str) do
    case Integer.parse(id_str) do
      {id, _} -> id
      :error -> nil
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(date_str), do: Date.from_iso8601!(date_str)
end

defmodule LedgrWeb.AccountTransactionHTML do
  use LedgrWeb, :html
  embed_templates "account_transaction_html/*"
end
