defmodule LedgrWeb.ExpenseController do
  use LedgrWeb, :controller

  alias Ledgr.Core.Expenses
  alias Ledgr.Core.Expenses.Expense
  alias Ledgr.Core.Accounting
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, _params) do
    expenses = Expenses.list_expenses()

    render(conn, :index, expenses: expenses)
  end

  def new(conn, _params) do
    changeset = Expenses.change_expense(%Expense{})

    render(conn, :new,
      changeset: changeset,
      action: dp(conn, "/expenses"),
      expense_account_options: Accounting.expense_account_options(),
      paid_from_account_options: Accounting.cash_or_payable_account_options()
    )
  end

  def create(conn, %{"expense" => attrs}) do
    # Convert pesos to cents
    attrs = MoneyHelper.convert_params_pesos_to_cents(attrs, [:amount_cents])

    case Expenses.create_expense_with_journal(attrs) do
      {:ok, expense} ->
        conn
        |> put_flash(:info, "Expense recorded.")
        |> redirect(to: dp(conn, "/expenses/#{expense.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        # Convert amount_cents back to pesos for form re-display
        changeset =
          changeset
          |> Map.put(:action, :insert)
          |> Ecto.Changeset.put_change(
            :amount_cents,
            MoneyHelper.cents_to_pesos(Ecto.Changeset.get_field(changeset, :amount_cents))
          )

        render(conn, :new,
          changeset: changeset,
          action: dp(conn, "/expenses"),
          expense_account_options: Accounting.expense_account_options(),
          paid_from_account_options: Accounting.cash_or_payable_account_options()
        )
    end
  end

  def show(conn, %{"id" => id}) do
    expense = Expenses.get_expense!(id)

    render(conn, :show, expense: expense)
  end

  def edit(conn, %{"id" => id}) do
    expense = Expenses.get_expense!(id)

    # Convert amount_cents to pesos for form display
    attrs = %{
      "amount_cents" => MoneyHelper.cents_to_pesos(expense.amount_cents)
    }

    changeset = Expenses.change_expense(expense, attrs)

    render(conn, :edit,
      expense: expense,
      changeset: changeset,
      action: dp(conn, "/expenses/#{expense.id}"),
      expense_account_options: Accounting.expense_account_options(),
      paid_from_account_options: Accounting.cash_or_payable_account_options()
    )
  end

  def update(conn, %{"id" => id, "expense" => expense_params}) do
    expense = Expenses.get_expense!(id)

    # Convert pesos to cents
    expense_params = MoneyHelper.convert_params_pesos_to_cents(expense_params, [:amount_cents])

    case Expenses.update_expense_with_journal(expense, expense_params) do
      {:ok, expense} ->
        conn
        |> put_flash(:info, "Expense updated successfully.")
        |> redirect(to: dp(conn, "/expenses/#{expense.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        # Convert amount_cents back to pesos for form re-display
        changeset =
          changeset
          |> Map.put(:action, :update)
          |> Ecto.Changeset.put_change(
            :amount_cents,
            MoneyHelper.cents_to_pesos(Ecto.Changeset.get_field(changeset, :amount_cents))
          )

        render(conn, :edit,
          expense: expense,
          changeset: changeset,
          action: dp(conn, "/expenses/#{expense.id}"),
          expense_account_options: Accounting.expense_account_options(),
          paid_from_account_options: Accounting.cash_or_payable_account_options()
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    expense = Expenses.get_expense!(id)

    case Expenses.delete_expense(expense) do
      {:ok, _expense} ->
        conn
        |> put_flash(:info, "Expense deleted successfully.")
        |> redirect(to: dp(conn, "/expenses"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to delete expense.")
        |> redirect(to: dp(conn, "/expenses/#{expense.id}"))
    end
  end
end

defmodule LedgrWeb.ExpenseHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents

  embed_templates "expense_html/*"
end
