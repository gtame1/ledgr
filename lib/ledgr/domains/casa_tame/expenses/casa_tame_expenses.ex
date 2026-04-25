defmodule Ledgr.Domains.CasaTame.Expenses do
  @moduledoc """
  Manages personal expenses for Casa Tame with dual-currency and category support.
  """

  import Ecto.Query, warn: false
  alias Ledgr.Repo

  alias Ledgr.Domains.CasaTame.Expenses.CasaTameExpense, as: Expense
  alias Ledgr.Domains.CasaTame.Expenses.ExpenseSplit
  alias Ledgr.Domains.CasaTame.Expenses.ExpenseAttachment
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry

  def list_expenses(opts \\ []) do
    query =
      from e in Expense,
        preload: [:expense_account, :paid_from_account, :expense_category, :attachments, splits: :account],
        order_by: [desc: e.date, desc: e.inserted_at]

    query
    |> maybe_filter_currency(opts[:currency])
    |> maybe_filter_category(opts[:category_id])
    |> maybe_filter_date_from(opts[:date_from])
    |> maybe_filter_date_to(opts[:date_to])
    |> Repo.all()
  end

  defp maybe_filter_currency(query, nil), do: query
  defp maybe_filter_currency(query, ""), do: query
  defp maybe_filter_currency(query, currency) do
    from e in query, where: e.currency == ^currency
  end

  defp maybe_filter_category(query, nil), do: query
  defp maybe_filter_category(query, ""), do: query
  defp maybe_filter_category(query, category_id) do
    from e in query, where: e.expense_category_id == ^category_id
  end

  defp maybe_filter_date_from(query, nil), do: query
  defp maybe_filter_date_from(query, ""), do: query
  defp maybe_filter_date_from(query, date_from) do
    date = if is_binary(date_from), do: Date.from_iso8601!(date_from), else: date_from
    from e in query, where: e.date >= ^date
  end

  defp maybe_filter_date_to(query, nil), do: query
  defp maybe_filter_date_to(query, ""), do: query
  defp maybe_filter_date_to(query, date_to) do
    date = if is_binary(date_to), do: Date.from_iso8601!(date_to), else: date_to
    from e in query, where: e.date <= ^date
  end

  def get_expense!(id) do
    Expense
    |> Repo.get!(id)
    |> Repo.preload([:expense_account, :paid_from_account, :expense_category, :attachments, splits: :account])
  end

  # ── Attachment helpers ─────────────────────────────────────────

  def get_attachment!(id), do: Repo.get!(ExpenseAttachment, id)

  def attach_receipt(expense_id, %Plug.Upload{} = upload) do
    with {:ok, stored_path} <- Ledgr.Receipts.save(upload) do
      %ExpenseAttachment{}
      |> ExpenseAttachment.changeset(%{
        expense_id: expense_id,
        filename: upload.filename,
        stored_path: stored_path,
        content_type: upload.content_type,
        file_size: file_size(upload.path)
      })
      |> Repo.insert()
    end
  end

  def delete_attachment(%ExpenseAttachment{} = attachment) do
    Ledgr.Receipts.delete(attachment.stored_path)
    Repo.delete(attachment)
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> nil
    end
  end

  def change_expense(%Expense{} = expense, attrs \\ %{}) do
    Expense.changeset(expense, attrs)
  end

  def create_expense_with_journal(attrs) do
    Repo.transaction(fn ->
      with {:ok, expense} <-
             %Expense{}
             |> Expense.changeset(attrs)
             |> Repo.insert(),
           {:ok, _entry} <- record_expense_journal(expense) do
        expense
      else
        {:error, changeset = %Ecto.Changeset{}} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Creates an expense with multiple payment splits.
  `splits` is a list of maps with `"account_id"` and `"amount_cents"` (already in cents).
  The total expense amount is derived from the sum of split amounts.
  """
  def create_expense_with_splits(attrs, splits) when is_list(splits) and splits != [] do
    total_cents = Enum.sum(Enum.map(splits, & &1["amount_cents"]))
    first_account_id = hd(splits)["account_id"]

    attrs =
      attrs
      |> Map.put("amount_cents", total_cents)
      |> Map.put("paid_from_account_id", first_account_id)

    Repo.transaction(fn ->
      with {:ok, expense} <- %Expense{} |> Expense.changeset(attrs) |> Repo.insert(),
           :ok <- insert_splits(expense, splits),
           {:ok, _entry} <- record_expense_journal_splits(expense, splits) do
        expense
      else
        {:error, changeset = %Ecto.Changeset{}} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates an expense and replaces its payment splits.
  """
  def update_expense_with_splits(%Expense{} = expense, attrs, splits) when is_list(splits) and splits != [] do
    total_cents = Enum.sum(Enum.map(splits, & &1["amount_cents"]))
    first_account_id = hd(splits)["account_id"]

    attrs =
      attrs
      |> Map.put("amount_cents", total_cents)
      |> Map.put("paid_from_account_id", first_account_id)

    Repo.transaction(fn ->
      with {:ok, updated} <- expense |> Expense.changeset(attrs) |> Repo.update(),
           :ok <- replace_splits(updated, splits),
           {:ok, _entry} <- update_expense_journal_splits(updated, splits) do
        updated
      else
        {:error, changeset = %Ecto.Changeset{}} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_expense_with_journal(%Expense{} = expense, attrs) do
    Repo.transaction(fn ->
      with {:ok, updated} <-
             expense
             |> Expense.changeset(attrs)
             |> Repo.update(),
           {:ok, _entry} <- update_expense_journal(updated) do
        updated
      else
        {:error, changeset = %Ecto.Changeset{}} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_expense(%Expense{} = expense) do
    Repo.transaction(fn ->
      reference = "Expense ##{expense.id}"

      journal_entry =
        from(je in JournalEntry, where: je.reference == ^reference)
        |> Repo.one()

      if journal_entry, do: Repo.delete!(journal_entry)
      Repo.delete!(expense)
    end)
  end

  # ── Split Helpers ──────────────────────────────────────────────

  defp insert_splits(expense, splits) do
    Enum.each(splits, fn split ->
      %ExpenseSplit{}
      |> ExpenseSplit.changeset(%{
        expense_id: expense.id,
        account_id: split["account_id"],
        amount_cents: split["amount_cents"]
      })
      |> Repo.insert!()
    end)

    :ok
  end

  defp replace_splits(expense, splits) do
    Repo.delete_all(from s in ExpenseSplit, where: s.expense_id == ^expense.id)
    insert_splits(expense, splits)
  end

  # ── Journal Entry Helpers ──────────────────────────────────────

  defp record_expense_journal(expense) do
    lines = [
      %{
        account_id: expense.expense_account_id,
        debit_cents: expense.amount_cents,
        credit_cents: 0,
        description: "Expense: #{expense.description}"
      },
      %{
        account_id: expense.paid_from_account_id,
        debit_cents: 0,
        credit_cents: expense.amount_cents,
        description: "Paid from account"
      }
    ]

    Accounting.create_journal_entry_with_lines(
      %{
        date: expense.date,
        entry_type: "personal_expense",
        reference: "Expense ##{expense.id}",
        description: expense.description,
        payee: expense.payee
      },
      lines
    )
  end

  defp update_expense_journal(expense) do
    reference = "Expense ##{expense.id}"
    je = from(j in JournalEntry, where: j.reference == ^reference) |> Repo.one()

    lines = [
      %{
        account_id: expense.expense_account_id,
        debit_cents: expense.amount_cents,
        credit_cents: 0,
        description: "Expense: #{expense.description}"
      },
      %{
        account_id: expense.paid_from_account_id,
        debit_cents: 0,
        credit_cents: expense.amount_cents,
        description: "Paid from account"
      }
    ]

    if je do
      Accounting.update_journal_entry_with_lines(
        je,
        %{date: expense.date, description: expense.description, payee: expense.payee},
        lines
      )
    else
      record_expense_journal(expense)
    end
  end

  defp record_expense_journal_splits(expense, splits) do
    lines = [
      %{
        account_id: expense.expense_account_id,
        debit_cents: expense.amount_cents,
        credit_cents: 0,
        description: "Expense: #{expense.description}"
      }
      | Enum.map(splits, fn split ->
          %{
            account_id: split["account_id"],
            debit_cents: 0,
            credit_cents: split["amount_cents"],
            description: "Paid from account"
          }
        end)
    ]

    Accounting.create_journal_entry_with_lines(
      %{
        date: expense.date,
        entry_type: "personal_expense",
        reference: "Expense ##{expense.id}",
        description: expense.description,
        payee: expense.payee
      },
      lines
    )
  end

  defp update_expense_journal_splits(expense, splits) do
    reference = "Expense ##{expense.id}"
    je = from(j in JournalEntry, where: j.reference == ^reference) |> Repo.one()

    lines = [
      %{
        account_id: expense.expense_account_id,
        debit_cents: expense.amount_cents,
        credit_cents: 0,
        description: "Expense: #{expense.description}"
      }
      | Enum.map(splits, fn split ->
          %{
            account_id: split["account_id"],
            debit_cents: 0,
            credit_cents: split["amount_cents"],
            description: "Paid from account"
          }
        end)
    ]

    if je do
      Accounting.update_journal_entry_with_lines(
        je,
        %{date: expense.date, description: expense.description, payee: expense.payee},
        lines
      )
    else
      record_expense_journal_splits(expense, splits)
    end
  end

  @doc "Returns expense totals grouped by expense_account_id and currency."
  def totals_by_account_and_currency(start_date, end_date) do
    from(e in Expense,
      where: e.date >= ^start_date and e.date <= ^end_date,
      join: a in assoc(e, :expense_account),
      group_by: [e.currency, a.id, a.code, a.name],
      select: %{
        currency: e.currency,
        account_code: a.code,
        account_name: a.name,
        total_cents: coalesce(sum(e.amount_cents), 0)
      },
      order_by: [asc: a.code]
    )
    |> Repo.all()
  end

  def total_by_currency(start_date, end_date) do
    results =
      from(e in Expense,
        where: e.date >= ^start_date and e.date <= ^end_date,
        group_by: e.currency,
        select: {e.currency, coalesce(sum(e.amount_cents), 0)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      usd: Map.get(results, "USD", 0),
      mxn: Map.get(results, "MXN", 0)
    }
  end
end
