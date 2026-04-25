defmodule LedgrWeb.Domains.CasaTame.ExpenseAttachmentController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.CasaTame.Expenses

  def create(conn, %{"expense_id" => expense_id, "attachment" => %{"file" => upload}}) do
    expense = Expenses.get_expense!(expense_id)

    case Expenses.attach_receipt(expense.id, upload) do
      {:ok, _attachment} ->
        conn
        |> put_flash(:info, "Receipt uploaded.")
        |> redirect(to: dp(conn, "/expenses/#{expense.id}"))

      {:error, reason} when is_binary(reason) ->
        conn
        |> put_flash(:error, reason)
        |> redirect(to: dp(conn, "/expenses/#{expense.id}"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Failed to upload receipt.")
        |> redirect(to: dp(conn, "/expenses/#{expense.id}"))
    end
  end

  def create(conn, %{"expense_id" => expense_id}) do
    conn
    |> put_flash(:error, "No file selected.")
    |> redirect(to: dp(conn, "/expenses/#{expense_id}"))
  end

  def delete(conn, %{"expense_id" => expense_id, "id" => attachment_id}) do
    attachment = Expenses.get_attachment!(attachment_id)
    Expenses.delete_attachment(attachment)

    conn
    |> put_flash(:info, "Receipt removed.")
    |> redirect(to: dp(conn, "/expenses/#{expense_id}"))
  end
end
