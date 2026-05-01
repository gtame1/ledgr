defmodule Ledgr.Domains.CasaTame.Bills do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.CasaTame.Bills.RecurringBill

  def list_bills do
    from(b in RecurringBill, where: b.is_active == true, order_by: [asc: b.next_due_date])
    |> Repo.all()
  end

  def list_all_bills do
    from(b in RecurringBill, order_by: [desc: b.is_active, asc: b.next_due_date])
    |> Repo.all()
  end

  def list_upcoming_bills(days \\ 30) do
    today = Ledgr.Domains.CasaTame.today()
    cutoff = Date.add(today, days)

    from(b in RecurringBill,
      where: b.is_active == true and b.next_due_date >= ^today and b.next_due_date <= ^cutoff,
      order_by: [asc: b.next_due_date]
    )
    |> Repo.all()
  end

  def list_bills_for_month(year, month) do
    first_day = Date.new!(year, month, 1)
    last_day = Date.end_of_month(first_day)

    # For recurring bills, we need to compute which dates they fall on this month
    active_bills = list_bills()

    Enum.reduce(active_bills, %{}, fn bill, acc ->
      dates = bill_dates_in_range(bill, first_day, last_day)

      Enum.reduce(dates, acc, fn date, inner_acc ->
        Map.update(inner_acc, date, [bill], fn existing -> existing ++ [bill] end)
      end)
    end)
  end

  def get_bill!(id), do: Repo.get!(RecurringBill, id)

  def change_bill(%RecurringBill{} = bill, attrs \\ %{}), do: RecurringBill.changeset(bill, attrs)

  def create_bill(attrs) do
    %RecurringBill{}
    |> RecurringBill.changeset(attrs)
    |> Repo.insert()
  end

  def update_bill(%RecurringBill{} = bill, attrs) do
    bill
    |> RecurringBill.changeset(attrs)
    |> Repo.update()
  end

  def delete_bill(%RecurringBill{} = bill), do: Repo.delete(bill)

  def mark_paid(%RecurringBill{frequency: "one_time"} = bill) do
    today = Ledgr.Domains.CasaTame.today()
    bill |> Ecto.Changeset.change(%{is_active: false, last_paid_date: today}) |> Repo.update()
  end

  def mark_paid(%RecurringBill{} = bill) do
    today = Ledgr.Domains.CasaTame.today()
    next_date = advance_due_date(bill)

    bill
    |> Ecto.Changeset.change(%{next_due_date: next_date, last_paid_date: today})
    |> Repo.update()
  end

  def advance_due_date(%RecurringBill{} = bill) do
    base = bill.next_due_date

    case bill.frequency do
      "weekly" -> Date.add(base, 7)
      "biweekly" -> Date.add(base, 14)
      "monthly" -> safe_add_months(base, 1, bill.day_of_month)
      "quarterly" -> safe_add_months(base, 3, bill.day_of_month)
      "annual" -> safe_add_months(base, 12, bill.day_of_month)
      "one_time" -> base
    end
  end

  # Add months while respecting day_of_month (handles Feb 30 → Feb 28, etc.)
  defp safe_add_months(date, months, preferred_day) do
    new_month = date.month + months
    new_year = date.year + div(new_month - 1, 12)
    new_month = rem(new_month - 1, 12) + 1

    day = preferred_day || date.day
    max_day = Date.days_in_month(Date.new!(new_year, new_month, 1))
    actual_day = min(day, max_day)

    Date.new!(new_year, new_month, actual_day)
  end

  # Returns the list of dates a bill falls on within a date range
  defp bill_dates_in_range(%RecurringBill{frequency: "one_time"} = bill, first_day, last_day) do
    if Date.compare(bill.next_due_date, first_day) != :lt and
         Date.compare(bill.next_due_date, last_day) != :gt do
      [bill.next_due_date]
    else
      []
    end
  end

  defp bill_dates_in_range(%RecurringBill{frequency: freq} = bill, first_day, last_day)
       when freq in ["weekly", "biweekly"] do
    interval = if freq == "weekly", do: 7, else: 14

    Stream.unfold(bill.next_due_date, fn date ->
      if Date.compare(date, last_day) == :gt, do: nil, else: {date, Date.add(date, interval)}
    end)
    |> Enum.filter(fn d -> Date.compare(d, first_day) != :lt end)
  end

  defp bill_dates_in_range(%RecurringBill{} = bill, first_day, last_day) do
    # Monthly/quarterly/annual — check if any occurrence falls in range
    day = bill.day_of_month || bill.next_due_date.day
    max_day = Date.days_in_month(first_day)
    actual_day = min(day, max_day)

    case Date.new(first_day.year, first_day.month, actual_day) do
      {:ok, date} ->
        if Date.compare(date, first_day) != :lt and Date.compare(date, last_day) != :gt do
          [date]
        else
          []
        end

      _ ->
        []
    end
  end
end
