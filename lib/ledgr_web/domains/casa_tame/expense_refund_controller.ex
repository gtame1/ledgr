defmodule LedgrWeb.Domains.CasaTame.ExpenseRefundController do
  use LedgrWeb, :controller

  alias Ledgr.Repo
  alias Ledgr.Domains.CasaTame.Expenses
  alias Ledgr.Domains.CasaTame.Expenses.ExpenseRefund

  # GET /app/casa-tame/expenses/:expense_id/refunds/new
  def new(conn, %{"expense_id" => expense_id}) do
    expense = Expenses.get_expense!(expense_id)
    already_refunded = Expenses.total_refunded_cents(expense)
    remaining_cents = expense.amount_cents - already_refunded

    changeset =
      Expenses.change_refund(%ExpenseRefund{}, %{
        "date" => Ledgr.Domains.CasaTame.today(),
        "currency" => expense.currency
      })

    render(conn, :new,
      expense: expense,
      changeset: changeset,
      remaining_cents: remaining_cents,
      refund_to_account_options: refund_to_options(expense.currency),
      action: dp(conn, "/expenses/#{expense_id}/refunds")
    )
  end

  # POST /app/casa-tame/expenses/:expense_id/refunds
  def create(conn, %{"expense_id" => expense_id, "refund" => refund_params}) do
    expense = Expenses.get_expense!(expense_id)

    case Expenses.create_refund(expense, refund_params) do
      {:ok, _refund} ->
        conn
        |> put_flash(:info, "Refund recorded.")
        |> redirect(to: dp(conn, "/expenses/#{expense_id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        already_refunded = Expenses.total_refunded_cents(expense)
        remaining_cents = expense.amount_cents - already_refunded

        render(conn, :new,
          expense: expense,
          changeset: changeset,
          remaining_cents: remaining_cents,
          refund_to_account_options: refund_to_options(expense.currency),
          action: dp(conn, "/expenses/#{expense_id}/refunds")
        )
    end
  end

  # DELETE /app/casa-tame/expenses/:expense_id/refunds/:id
  def delete(conn, %{"expense_id" => expense_id, "id" => refund_id}) do
    refund = Repo.get!(ExpenseRefund, refund_id)

    case Expenses.delete_refund(refund) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Refund removed.")
        |> redirect(to: dp(conn, "/expenses/#{expense_id}"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Failed to remove refund.")
        |> redirect(to: dp(conn, "/expenses/#{expense_id}"))
    end
  end

  # ── Private ────────────────────────────────────────────────────

  @paid_from_ranges [
    {"Cash & Bank",      "1000", "1019", "USD"},
    {"Credit Cards",     "2000", "2009", "USD"},
    {"Accounts Payable", "2010", "2019", "USD"},
    {"Cash & Bank",      "1100", "1119", "MXN"},
    {"Credit Cards",     "2100", "2109", "MXN"},
    {"Accounts Payable", "2110", "2119", "MXN"}
  ]

  defp refund_to_options(currency) do
    import Ecto.Query
    alias Ledgr.Core.Accounting.Account

    ranges = Enum.filter(@paid_from_ranges, fn {_, _, _, c} -> c == currency end)

    accounts =
      Enum.flat_map(ranges, fn {_, from_code, to_code, _} ->
        Repo.all(
          from a in Account,
            where: a.code >= ^from_code and a.code <= ^to_code,
            order_by: a.code
        )
      end)

    Enum.map(accounts, &{"#{&1.code} – #{&1.name}", &1.id})
  end
end

defmodule LedgrWeb.Domains.CasaTame.ExpenseRefundHTML do
  use LedgrWeb, :html

  embed_templates "expense_refund_html/*"
end
