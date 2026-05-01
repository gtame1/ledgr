defmodule LedgrWeb.Domains.MrMunchMe.OrderPaymentController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Orders
  alias Ledgr.Core.{Accounting, Partners}
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, _params) do
    payments = Orders.list_all_payments()

    render(conn, :index, payments: payments)
  end

  def show(conn, %{"id" => id}) do
    payment = Orders.get_order_payment!(id)

    render(conn, :show, payment: payment)
  end

  def edit(conn, %{"id" => id}) do
    payment = Orders.get_order_payment!(id)

    # Convert amounts from cents to pesos for form display
    amount_pesos =
      if payment.amount_cents, do: MoneyHelper.cents_to_pesos(payment.amount_cents), else: nil

    customer_amount_pesos =
      if payment.customer_amount_cents,
        do: MoneyHelper.cents_to_pesos(payment.customer_amount_cents),
        else: nil

    partner_amount_pesos =
      if payment.partner_amount_cents,
        do: MoneyHelper.cents_to_pesos(payment.partner_amount_cents),
        else: nil

    attrs = %{
      "payment_date" => payment.payment_date,
      "amount" => amount_pesos,
      "paid_to_account_id" => payment.paid_to_account_id,
      "method" => payment.method,
      "note" => payment.note,
      "customer_amount" => customer_amount_pesos,
      "partner_amount" => partner_amount_pesos,
      "partner_id" => payment.partner_id,
      "partner_payable_account_id" => payment.partner_payable_account_id
    }

    changeset = Orders.change_order_payment(payment, attrs)

    render(conn, :edit,
      payment: payment,
      changeset: changeset,
      paid_to_account_options: Accounting.cash_or_payable_account_options(),
      partner_options: Partners.partner_select_options(),
      liability_account_options: Accounting.liability_account_options()
    )
  end

  def update(conn, %{"id" => id, "order_payment" => params}) do
    payment = Orders.get_order_payment!(id)

    # Convert amounts from pesos to cents
    amount_cents =
      if params["amount"],
        do: MoneyHelper.pesos_to_cents(params["amount"]),
        else: payment.amount_cents

    customer_amount_cents =
      if params["customer_amount"],
        do: MoneyHelper.pesos_to_cents(params["customer_amount"]),
        else: payment.customer_amount_cents

    partner_amount_cents =
      if params["partner_amount"],
        do: MoneyHelper.pesos_to_cents(params["partner_amount"]),
        else: payment.partner_amount_cents

    attrs =
      params
      |> Map.put("amount_cents", amount_cents)
      |> Map.put("customer_amount_cents", customer_amount_cents)
      |> Map.put("partner_amount_cents", partner_amount_cents)
      |> Map.drop(["amount", "customer_amount", "partner_amount"])

    case Orders.update_order_payment(payment, attrs) do
      {:ok, payment} ->
        conn
        |> put_flash(:info, "Payment updated successfully.")
        |> redirect(to: dp(conn, "/order_payments/#{payment.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit,
          payment: payment,
          changeset: changeset,
          paid_to_account_options: Accounting.cash_or_payable_account_options(),
          partner_options: Partners.partner_select_options(),
          liability_account_options: Accounting.liability_account_options()
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    payment = Orders.get_order_payment!(id)

    case Orders.delete_order_payment(payment) do
      {:ok, _payment} ->
        conn
        |> put_flash(:info, "Payment deleted successfully.")
        |> redirect(to: dp(conn, "/order_payments"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to delete payment.")
        |> redirect(to: dp(conn, "/order_payments/#{payment.id}"))
    end
  end
end

defmodule LedgrWeb.Domains.MrMunchMe.OrderPaymentHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents

  embed_templates "order_payment_html/*"
end
