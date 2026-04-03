defmodule LedgrWeb.Domains.CasaTame.BillController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.CasaTame.Bills
  alias Ledgr.Domains.CasaTame.Bills.RecurringBill
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, _params) do
    bills = Bills.list_all_bills()
    today = Ledgr.Domains.CasaTame.today()
    year = today.year
    month = today.month
    first_day = Date.new!(year, month, 1)
    last_day = Date.end_of_month(first_day)

    # Build calendar grid (Sunday-start weeks)
    day_of_week = Date.day_of_week(first_day, :sunday)
    calendar_start = Date.add(first_day, -(day_of_week - 1))
    calendar_end_raw = Date.add(last_day, 7 - Date.day_of_week(last_day, :sunday))

    calendar_end =
      if Date.diff(calendar_end_raw, calendar_start) < 35,
        do: Date.add(calendar_end_raw, 7),
        else: calendar_end_raw

    # Group active bills by their next_due_date within this month
    bills_by_date =
      Enum.reduce(bills, %{}, fn bill, acc ->
        if bill.is_active && bill.next_due_date != nil &&
             Date.compare(bill.next_due_date, first_day) != :lt &&
             Date.compare(bill.next_due_date, last_day) != :gt do
          Map.update(acc, bill.next_due_date, [bill], &[bill | &1])
        else
          acc
        end
      end)

    # Split into today's bills and upcoming
    today_bills = Enum.filter(bills, fn b -> b.is_active && b.next_due_date == today end)

    cutoff_30d = Date.add(today, 30)

    upcoming_bills =
      bills
      |> Enum.filter(fn b ->
        b.is_active && b.next_due_date != nil &&
          Date.compare(b.next_due_date, today) == :gt &&
          Date.compare(b.next_due_date, cutoff_30d) != :gt
      end)
      |> Enum.sort_by(& &1.next_due_date, Date)

    # Bills due in the next 30 days that haven't been paid yet
    cutoff = Date.add(today, 30)

    upcoming_unpaid =
      Enum.filter(bills, fn b ->
        b.is_active &&
          b.next_due_date != nil &&
          Date.compare(b.next_due_date, today) != :lt &&
          Date.compare(b.next_due_date, cutoff) != :gt &&
          (b.last_paid_date == nil || Date.compare(b.last_paid_date, b.next_due_date) == :lt)
      end)

    monthly_total =
      upcoming_unpaid
      |> Enum.filter(& &1.amount_cents != nil)
      |> Enum.reduce(0, fn b, acc -> acc + b.amount_cents end)

    monthly_count = length(upcoming_unpaid)

    # Bills paid this month
    paid_this_month =
      bills
      |> Enum.filter(fn b ->
        b.last_paid_date != nil &&
          Date.compare(b.last_paid_date, first_day) != :lt &&
          Date.compare(b.last_paid_date, last_day) != :gt
      end)
      |> Enum.sort_by(& &1.last_paid_date, {:desc, Date})

    render(conn, :index,
      bills: bills,
      today: today,
      year: year,
      month: month,
      first_day: first_day,
      last_day: last_day,
      calendar_start: calendar_start,
      calendar_end: calendar_end,
      bills_by_date: bills_by_date,
      today_bills: today_bills,
      upcoming_bills: upcoming_bills,
      monthly_total: monthly_total,
      monthly_count: monthly_count,
      paid_this_month: paid_this_month,
      paid_from_options: paid_from_options()
    )
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

  def mark_paid(conn, %{"id" => id} = params) do
    bill = Bills.get_bill!(id)
    paid_from_account_id = params["paid_from_account_id"]

    case Bills.mark_paid(bill) do
      {:ok, _} ->
        # Auto-create expense if bill has an amount and a paid_from account was selected
        expense_msg =
          if bill.amount_cents && paid_from_account_id && paid_from_account_id != "" do
            # Find a matching expense category based on bill category
            expense_account_id = bill_category_to_expense_account(bill.category)

            attrs = %{
              "description" => bill.name,
              "date" => to_string(Ledgr.Domains.CasaTame.today()),
              "amount_cents" => bill.amount_cents,
              "currency" => bill.currency || "MXN",
              "expense_account_id" => expense_account_id,
              "paid_from_account_id" => paid_from_account_id
            }

            case Ledgr.Domains.CasaTame.Expenses.create_expense_with_journal(attrs) do
              {:ok, _expense} -> " Expense recorded."
              {:error, _} -> " (Failed to create expense)"
            end
          else
            ""
          end

        msg = if bill.frequency == "one_time",
          do: "Bill marked as paid and archived.#{expense_msg}",
          else: "Bill marked as paid. Next due: #{Bills.advance_due_date(bill)}.#{expense_msg}"

        conn |> put_flash(:info, msg) |> redirect(to: dp(conn, "/bills"))

      {:error, _} ->
        conn |> put_flash(:error, "Failed to mark as paid.") |> redirect(to: dp(conn, "/bills"))
    end
  end

  defp paid_from_options do
    import Ecto.Query
    alias Ledgr.Core.Accounting.Account

    Ledgr.Repo.all(
      from a in Account,
        where: (a.code >= "1000" and a.code <= "1019")
            or (a.code >= "1100" and a.code <= "1139")
            or (a.code >= "2000" and a.code <= "2019")
            or (a.code >= "2100" and a.code <= "2119"),
        order_by: [asc: a.code]
    )
    |> Enum.map(&{&1.name, &1.id})
  end

  # Map bill categories to expense account codes
  defp bill_category_to_expense_account(category) do
    # Find a reasonable default expense account for each bill category
    code = case category do
      "credit_card" -> "6060"    # Financial
      "utility" -> "6020"        # Utilities
      "loan" -> "6060"           # Financial
      "insurance" -> "6070"      # Health & Personal Care
      "subscription" -> "6050"   # Entertainment
      _ -> "6099"                # Other
    end

    case Ledgr.Core.Accounting.get_account_by_code(code) do
      nil -> nil
      account -> account.id
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
