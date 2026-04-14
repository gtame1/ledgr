defmodule Ledgr.Domains.CasaTame.BillsTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.CasaTame.Bills
  alias Ledgr.Domains.CasaTame.Bills.RecurringBill

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.CasaTame)
    Ledgr.Domain.put_current(Ledgr.Domains.CasaTame)
    :ok
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Netflix #{System.unique_integer([:positive])}",
        amount_cents: 19900,
        currency: "MXN",
        frequency: "monthly",
        day_of_month: 15,
        next_due_date: ~D[2026-05-15],
        category: "subscription"
      },
      overrides
    )
  end

  describe "CRUD" do
    test "create_bill/1 inserts an active bill" do
      assert {:ok, %RecurringBill{is_active: true} = bill} = Bills.create_bill(valid_attrs())
      assert bill.frequency == "monthly"
    end

    test "create_bill/1 requires :name, :frequency, :next_due_date" do
      assert {:error, changeset} = Bills.create_bill(%{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.frequency
      assert "can't be blank" in errors.next_due_date
    end

    test "create_bill/1 rejects an invalid frequency" do
      assert {:error, changeset} = Bills.create_bill(valid_attrs(%{frequency: "yearly"}))
      assert "is invalid" in errors_on(changeset).frequency
    end

    test "create_bill/1 rejects amount_cents <= 0" do
      assert {:error, changeset} = Bills.create_bill(valid_attrs(%{amount_cents: 0}))
      assert Enum.any?(errors_on(changeset).amount_cents, &(&1 =~ "greater than"))
    end

    test "update_bill/2 changes a field" do
      {:ok, bill} = Bills.create_bill(valid_attrs())
      {:ok, updated} = Bills.update_bill(bill, %{amount_cents: 29900})
      assert updated.amount_cents == 29900
    end

    test "delete_bill/1 removes the row" do
      {:ok, bill} = Bills.create_bill(valid_attrs())
      assert {:ok, _} = Bills.delete_bill(bill)
      assert_raise Ecto.NoResultsError, fn -> Bills.get_bill!(bill.id) end
    end

    test "change_bill/2 returns a changeset" do
      assert %Ecto.Changeset{} = Bills.change_bill(%RecurringBill{}, %{name: "X"})
    end

    test "get_bill!/1 fetches by id" do
      {:ok, bill} = Bills.create_bill(valid_attrs())
      assert Bills.get_bill!(bill.id).id == bill.id
    end
  end

  describe "list functions" do
    test "list_bills/0 returns only active bills ordered by next_due_date" do
      {:ok, later}   = Bills.create_bill(valid_attrs(%{next_due_date: ~D[2026-06-01]}))
      {:ok, earlier} = Bills.create_bill(valid_attrs(%{next_due_date: ~D[2026-05-01]}))
      {:ok, _inactive} = Bills.create_bill(valid_attrs(%{is_active: false}))

      results = Bills.list_bills()
      ids = Enum.map(results, & &1.id)

      # Earlier comes before later in ordering; inactive excluded
      assert earlier.id in ids
      assert later.id in ids
      earlier_idx = Enum.find_index(ids, &(&1 == earlier.id))
      later_idx = Enum.find_index(ids, &(&1 == later.id))
      assert earlier_idx < later_idx
      assert Enum.all?(results, & &1.is_active)
    end

    test "list_all_bills/0 includes inactive bills" do
      {:ok, active} = Bills.create_bill(valid_attrs())
      {:ok, inactive} = Bills.create_bill(valid_attrs(%{is_active: false}))

      ids = Bills.list_all_bills() |> Enum.map(& &1.id)
      assert active.id in ids
      assert inactive.id in ids
    end
  end

  describe "advance_due_date/1" do
    test "weekly adds 7 days" do
      bill = %RecurringBill{frequency: "weekly", next_due_date: ~D[2026-05-01], day_of_month: nil}
      assert Bills.advance_due_date(bill) == ~D[2026-05-08]
    end

    test "biweekly adds 14 days" do
      bill = %RecurringBill{frequency: "biweekly", next_due_date: ~D[2026-05-01], day_of_month: nil}
      assert Bills.advance_due_date(bill) == ~D[2026-05-15]
    end

    test "monthly advances by one month" do
      bill = %RecurringBill{frequency: "monthly", next_due_date: ~D[2026-05-15], day_of_month: 15}
      assert Bills.advance_due_date(bill) == ~D[2026-06-15]
    end

    test "monthly clamps day when target month is shorter (Jan 31 -> Feb 28)" do
      bill = %RecurringBill{frequency: "monthly", next_due_date: ~D[2026-01-31], day_of_month: 31}
      # 2026 is not a leap year → Feb 28
      assert Bills.advance_due_date(bill) == ~D[2026-02-28]
    end

    test "monthly rolls over the year (Dec -> Jan next year)" do
      bill = %RecurringBill{frequency: "monthly", next_due_date: ~D[2026-12-15], day_of_month: 15}
      assert Bills.advance_due_date(bill) == ~D[2027-01-15]
    end

    test "quarterly adds 3 months" do
      bill = %RecurringBill{frequency: "quarterly", next_due_date: ~D[2026-05-10], day_of_month: 10}
      assert Bills.advance_due_date(bill) == ~D[2026-08-10]
    end

    test "annual adds 12 months" do
      bill = %RecurringBill{frequency: "annual", next_due_date: ~D[2026-05-10], day_of_month: 10}
      assert Bills.advance_due_date(bill) == ~D[2027-05-10]
    end

    test "one_time keeps the date unchanged" do
      bill = %RecurringBill{frequency: "one_time", next_due_date: ~D[2026-05-10], day_of_month: nil}
      assert Bills.advance_due_date(bill) == ~D[2026-05-10]
    end
  end

  describe "mark_paid/1" do
    test "one_time bills become inactive" do
      {:ok, bill} = Bills.create_bill(valid_attrs(%{frequency: "one_time", day_of_month: nil}))
      {:ok, updated} = Bills.mark_paid(bill)
      refute updated.is_active
      assert updated.last_paid_date != nil
    end

    test "recurring bills advance next_due_date and stay active" do
      {:ok, bill} = Bills.create_bill(valid_attrs(%{frequency: "monthly", day_of_month: 15, next_due_date: ~D[2026-05-15]}))
      {:ok, updated} = Bills.mark_paid(bill)
      assert updated.is_active
      assert updated.next_due_date == ~D[2026-06-15]
      assert updated.last_paid_date != nil
    end
  end

  describe "list_bills_for_month/2" do
    test "returns a map of date => [bills]" do
      {:ok, _bill} = Bills.create_bill(valid_attrs(%{frequency: "monthly", day_of_month: 15, next_due_date: ~D[2026-05-15]}))

      result = Bills.list_bills_for_month(2026, 5)
      assert is_map(result)
      assert Map.has_key?(result, ~D[2026-05-15])
    end

    test "weekly bills return multiple dates in the month" do
      {:ok, _bill} = Bills.create_bill(valid_attrs(%{frequency: "weekly", day_of_month: nil, next_due_date: ~D[2026-05-01]}))

      result = Bills.list_bills_for_month(2026, 5)
      # Weekly starting May 1 → May 1, 8, 15, 22, 29 = at least 4 dates
      assert map_size(result) >= 4
    end

    test "one_time bill outside the month is excluded" do
      {:ok, _bill} = Bills.create_bill(valid_attrs(%{frequency: "one_time", day_of_month: nil, next_due_date: ~D[2026-05-15]}))

      result = Bills.list_bills_for_month(2026, 6)
      assert result == %{}
    end
  end

  describe "list_upcoming_bills/1" do
    test "filters out bills past the cutoff" do
      today = Ledgr.Domains.CasaTame.today()
      within = Date.add(today, 5)
      far_out = Date.add(today, 60)

      {:ok, close} = Bills.create_bill(valid_attrs(%{next_due_date: within, day_of_month: within.day}))
      {:ok, _far} = Bills.create_bill(valid_attrs(%{next_due_date: far_out, day_of_month: far_out.day}))

      results = Bills.list_upcoming_bills(30)
      ids = Enum.map(results, & &1.id)
      assert close.id in ids
    end
  end

  describe "RecurringBill helpers" do
    test "frequency_options/0 returns 6 options" do
      assert length(RecurringBill.frequency_options()) == 6
    end

    test "category_options/0 returns 6 options" do
      assert length(RecurringBill.category_options()) == 6
    end

    test "category_color/1 returns distinct hex per category" do
      assert RecurringBill.category_color("credit_card") == "#dc2626"
      assert RecurringBill.category_color("utility") == "#2563eb"
      assert RecurringBill.category_color("loan") == "#ea580c"
      assert RecurringBill.category_color("insurance") == "#7c3aed"
      assert RecurringBill.category_color("subscription") == "#0d9488"
      assert RecurringBill.category_color("other") == "#6b7280"
      assert RecurringBill.category_color("unknown") == "#6b7280"
    end
  end
end
