defmodule Ledgr.Core.Expenses do
  @moduledoc """
  Manages business expenses (OPEX, generic costs).
  """

  import Ecto.Query, warn: false
  alias Ledgr.Repo

  alias Ledgr.Core.Expenses.Expense
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry

  # ---------- PUBLIC API ----------

  @doc "Sum of amount_cents for expenses within the given date range."
  def total_expenses_cents(start_date, end_date) do
    from(e in Expense,
      where: e.date >= ^start_date and e.date <= ^end_date,
      select: coalesce(sum(e.amount_cents), 0)
    )
    |> Repo.one()
  end

  def list_expenses() do
    query =
      from e in Expense,
        preload: [:expense_account, :paid_from_account],
        order_by: [desc: e.date, desc: e.inserted_at]

    Repo.all(query)
  end

  def get_expense!(id) do
    Expense
    |> Repo.get!(id)
    |> Repo.preload([:expense_account, :paid_from_account])
  end

  def change_expense(%Expense{} = expense, attrs \\ %{}), do: Expense.changeset(expense, attrs)

  def create_expense(attrs), do: create_expense_with_journal(attrs)

  def update_expense(%Expense{} = expense, attrs), do: update_expense_with_journal(expense, attrs)

  def update_expense_with_journal(%Expense{} = expense, attrs) do
    # amount_cents should already be in cents (converted in controller)
    # No conversion needed here

    Repo.transaction(fn ->
      with {:ok, updated_expense} <-
             expense
             |> Expense.changeset(attrs)
             |> Repo.update(),
           {:ok, _entry} <- Accounting.update_expense_journal_entry(updated_expense) do
        updated_expense
      else
        {:error, changeset = %Ecto.Changeset{}} ->
          Repo.rollback(changeset)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def create_expense_with_journal(attrs) do
    # amount_cents should already be in cents (converted in controller)
    # No conversion needed here

    Repo.transaction(fn ->
      with {:ok, expense} <-
             %Expense{}
             |> Expense.changeset(attrs)
             |> Repo.insert(),
           {:ok, _entry} <- Accounting.record_expense(expense) do
        expense
      else
        {:error, changeset = %Ecto.Changeset{}} ->
          Repo.rollback(changeset)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  # you can keep a simple create_expense if you want it without accounting

  def delete_expense(%Expense{} = expense) do
    Repo.transaction(fn ->
      # Find and delete the related journal entry
      reference = "Expense ##{expense.id}"

      journal_entry =
        from(je in JournalEntry, where: je.reference == ^reference)
        |> Repo.one()

      if journal_entry do
        Repo.delete!(journal_entry)
      end

      # Delete the expense
      Repo.delete!(expense)
    end)
  end
end
