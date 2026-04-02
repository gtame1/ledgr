defmodule LedgrWeb.Domains.CasaTame.BillController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.CasaTame.Bills
  alias Ledgr.Domains.CasaTame.Bills.RecurringBill
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, _params) do
    bills = Bills.list_all_bills()
    today = Ledgr.Domains.CasaTame.today()

    render(conn, :index, bills: bills, today: today)
  end

  def calendar(conn, params) do
    today = Ledgr.Domains.CasaTame.today()

    year = case params["year"] do
      nil -> today.year
      y -> String.to_integer(y)
    end

    month = case params["month"] do
      nil -> today.month
      m -> String.to_integer(m)
    end

    month = max(1, min(12, month))

    bills_by_date = Bills.list_bills_for_month(year, month)

    first_day = Date.new!(year, month, 1)
    last_day = Date.end_of_month(first_day)

    weekday = Date.day_of_week(first_day)
    days_from_sunday = if weekday == 7, do: 0, else: weekday
    calendar_start = Date.add(first_day, -days_from_sunday)
    calendar_end = Date.add(calendar_start, 41)

    render(conn, :calendar,
      year: year,
      month: month,
      first_day: first_day,
      last_day: last_day,
      calendar_start: calendar_start,
      calendar_end: calendar_end,
      bills_by_date: bills_by_date,
      today: today
    )
  end

  def new(conn, _params) do
    changeset = Bills.change_bill(%RecurringBill{
      next_due_date: Ledgr.Domains.CasaTame.today(),
      currency: "MXN",
      frequency: "monthly"
    })

    render(conn, :new,
      changeset: changeset,
      action: dp(conn, "/bills")
    )
  end

  def create(conn, %{"recurring_bill" => attrs}) do
    attrs = MoneyHelper.convert_params_pesos_to_cents(attrs, [:amount_cents])

    case Bills.create_bill(attrs) do
      {:ok, _bill} ->
        conn |> put_flash(:info, "Bill created.") |> redirect(to: dp(conn, "/bills"))

      {:error, changeset} ->
        render(conn, :new, changeset: changeset, action: dp(conn, "/bills"))
    end
  end

  def edit(conn, %{"id" => id}) do
    bill = Bills.get_bill!(id)

    attrs =
      if bill.amount_cents do
        %{"amount_cents" => MoneyHelper.cents_to_pesos(bill.amount_cents)}
      else
        %{}
      end

    changeset = Bills.change_bill(bill, attrs)

    render(conn, :edit,
      bill: bill,
      changeset: changeset,
      action: dp(conn, "/bills/#{bill.id}")
    )
  end

  def update(conn, %{"id" => id, "recurring_bill" => attrs}) do
    bill = Bills.get_bill!(id)
    attrs = MoneyHelper.convert_params_pesos_to_cents(attrs, [:amount_cents])

    case Bills.update_bill(bill, attrs) do
      {:ok, _bill} ->
        conn |> put_flash(:info, "Bill updated.") |> redirect(to: dp(conn, "/bills"))

      {:error, changeset} ->
        render(conn, :edit, bill: bill, changeset: changeset, action: dp(conn, "/bills/#{bill.id}"))
    end
  end

  def delete(conn, %{"id" => id}) do
    bill = Bills.get_bill!(id)
    {:ok, _} = Bills.delete_bill(bill)
    conn |> put_flash(:info, "Bill deleted.") |> redirect(to: dp(conn, "/bills"))
  end

  def mark_paid(conn, %{"id" => id}) do
    bill = Bills.get_bill!(id)

    case Bills.mark_paid(bill) do
      {:ok, _} ->
        msg = if bill.frequency == "one_time", do: "Bill marked as paid and archived.", else: "Bill marked as paid. Next due: #{Bills.advance_due_date(bill)}."
        conn |> put_flash(:info, msg) |> redirect(to: dp(conn, "/bills"))

      {:error, _} ->
        conn |> put_flash(:error, "Failed to mark as paid.") |> redirect(to: dp(conn, "/bills"))
    end
  end

  # Helper for calendar nav
  def prev_month(year, month) when month == 1, do: %{year: year - 1, month: 12}
  def prev_month(year, month), do: %{year: year, month: month - 1}

  def next_month(year, month) when month == 12, do: %{year: year + 1, month: 1}
  def next_month(year, month), do: %{year: year, month: month + 1}
end

defmodule LedgrWeb.Domains.CasaTame.BillHTML do
  use LedgrWeb, :html

  embed_templates "bill_html/*"

  def prev_month(year, month) when month == 1, do: %{year: year - 1, month: 12}
  def prev_month(year, month), do: %{year: year, month: month - 1}

  def next_month(year, month) when month == 12, do: %{year: year + 1, month: 1}
  def next_month(year, month), do: %{year: year, month: month + 1}
end
