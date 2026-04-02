defmodule Ledgr.Domains.CasaTame.ExpensesTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.CasaTame.Expenses
  alias Ledgr.Domains.CasaTame.Expenses.CasaTameExpense, as: Expense
  alias Ledgr.Core.Accounting
  alias Ledgr.Repo

  import Ecto.Query

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.CasaTame)
    Ledgr.Domain.put_current(Ledgr.Domains.CasaTame)
    casa_tame_accounts_fixture()
    :ok
  end

  # ── Fixtures ────────────────────────────────────────────────────────────

  defp casa_tame_accounts_fixture do
    accounts = [
      %{code: "1000", name: "Cash USD",          type: "asset",   normal_balance: "debit",  is_cash: true},
      %{code: "1100", name: "Cash MXN",          type: "asset",   normal_balance: "debit",  is_cash: true},
      %{code: "1010", name: "Checking USD",      type: "asset",   normal_balance: "debit",  is_cash: true},
      %{code: "2000", name: "Credit Card USD",   type: "liability", normal_balance: "credit", is_cash: false},
      %{code: "2100", name: "Credit Card MXN",   type: "liability", normal_balance: "credit", is_cash: false},
      %{code: "3000", name: "Owner's Equity",    type: "equity",  normal_balance: "credit", is_cash: false},
      %{code: "3050", name: "Retained Earnings", type: "equity",  normal_balance: "credit", is_cash: false},
      %{code: "4000", name: "Wages USD",         type: "revenue", normal_balance: "credit", is_cash: false},
      %{code: "4010", name: "Wages MXN",         type: "revenue", normal_balance: "credit", is_cash: false},
      %{code: "4050", name: "Other Income",      type: "revenue", normal_balance: "credit", is_cash: false},
      %{code: "6000", name: "Housing",           type: "expense", normal_balance: "debit",  is_cash: false},
      %{code: "6010", name: "Food",              type: "expense", normal_balance: "debit",  is_cash: false},
      %{code: "6020", name: "Transport",         type: "expense", normal_balance: "debit",  is_cash: false}
    ]

    Enum.each(accounts, fn attrs ->
      case Accounting.get_account_by_code(attrs.code) do
        nil -> {:ok, _} = Accounting.create_account(attrs)
        _ -> :ok
      end
    end)
  end

  defp expense_account, do: Accounting.get_account_by_code!("6000")
  defp usd_cash_account, do: Accounting.get_account_by_code!("1000")
  defp mxn_cash_account, do: Accounting.get_account_by_code!("1100")
  defp usd_checking_account, do: Accounting.get_account_by_code!("1010")
  defp food_account, do: Accounting.get_account_by_code!("6010")

  defp expense_attrs(overrides \\ %{}) do
    Enum.into(overrides, %{
      date: ~D[2026-01-15],
      description: "Test expense #{System.unique_integer([:positive])}",
      amount_cents: 50_000,
      currency: "MXN",
      expense_account_id: expense_account().id,
      paid_from_account_id: mxn_cash_account().id
    })
  end

  defp expense_fixture(overrides \\ %{}) do
    {:ok, expense} = Expenses.create_expense_with_journal(expense_attrs(overrides))
    expense
  end

  # ── list_expenses/1 ─────────────────────────────────────────────────────

  describe "list_expenses/1" do
    test "returns all expenses with associations preloaded" do
      expense = expense_fixture()
      found = Enum.find(Expenses.list_expenses(), &(&1.id == expense.id))
      assert found != nil
      assert %Accounting.Account{} = found.expense_account
      assert %Accounting.Account{} = found.paid_from_account
    end

    test "returns empty list when no expenses exist" do
      assert Expenses.list_expenses() == []
    end

    test "orders by date descending" do
      _older = expense_fixture(%{date: ~D[2026-01-01]})
      _newer = expense_fixture(%{date: ~D[2026-01-20]})

      dates = Expenses.list_expenses() |> Enum.map(& &1.date)
      assert dates == Enum.sort(dates, {:desc, Date})
    end

    test "filters by currency" do
      expense_fixture(%{currency: "MXN"})
      expense_fixture(%{currency: "USD", paid_from_account_id: usd_checking_account().id})

      mxn = Expenses.list_expenses(currency: "MXN")
      usd = Expenses.list_expenses(currency: "USD")

      assert Enum.all?(mxn, &(&1.currency == "MXN"))
      assert Enum.all?(usd, &(&1.currency == "USD"))
    end

    test "filters by date range" do
      _jan = expense_fixture(%{date: ~D[2026-01-10]})
      _feb = expense_fixture(%{date: ~D[2026-02-10]})

      results = Expenses.list_expenses(date_from: ~D[2026-02-01], date_to: ~D[2026-02-28])
      assert Enum.all?(results, &(&1.date >= ~D[2026-02-01]))
      assert Enum.all?(results, &(&1.date <= ~D[2026-02-28]))
    end

    test "filters by date range given as strings" do
      expense_fixture(%{date: ~D[2026-03-05]})
      expense_fixture(%{date: ~D[2026-01-05]})

      results = Expenses.list_expenses(date_from: "2026-03-01", date_to: "2026-03-31")
      assert Enum.all?(results, &(&1.date >= ~D[2026-03-01]))
    end

    test "empty string filter is ignored" do
      expense_fixture()
      assert Expenses.list_expenses(currency: "") |> length() >= 1
    end
  end

  # ── get_expense!/1 ──────────────────────────────────────────────────────

  describe "get_expense!/1" do
    test "returns expense with associations preloaded" do
      expense = expense_fixture()
      found = Expenses.get_expense!(expense.id)
      assert found.id == expense.id
      assert %Accounting.Account{} = found.expense_account
      assert %Accounting.Account{} = found.paid_from_account
    end

    test "raises Ecto.NoResultsError for unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        Expenses.get_expense!(0)
      end
    end
  end

  # ── change_expense/2 ────────────────────────────────────────────────────

  describe "change_expense/2" do
    test "returns a changeset for an existing expense" do
      expense = expense_fixture()
      assert %Ecto.Changeset{} = Expenses.change_expense(expense, %{description: "Updated"})
    end

    test "returns a changeset for a new expense struct" do
      assert %Ecto.Changeset{} = Expenses.change_expense(%Expense{})
    end
  end

  # ── create_expense_with_journal/1 ───────────────────────────────────────

  describe "create_expense_with_journal/1" do
    test "persists expense with correct fields" do
      attrs = expense_attrs(%{description: "Groceries", amount_cents: 120_000, payee: "Walmart"})
      assert {:ok, %Expense{} = expense} = Expenses.create_expense_with_journal(attrs)
      assert expense.description == "Groceries"
      assert expense.amount_cents == 120_000
      assert expense.payee == "Walmart"
      assert expense.currency == "MXN"
    end

    test "creates an associated journal entry" do
      {:ok, expense} = Expenses.create_expense_with_journal(expense_attrs())
      reference = "Expense ##{expense.id}"
      entry = Repo.one(from je in Ledgr.Core.Accounting.JournalEntry, where: je.reference == ^reference)
      assert entry != nil
      assert entry.entry_type == "personal_expense"
    end

    test "creates journal entry with correct debit/credit lines" do
      {:ok, expense} = Expenses.create_expense_with_journal(expense_attrs(%{amount_cents: 80_000}))
      reference = "Expense ##{expense.id}"
      entry = Repo.one(from je in Ledgr.Core.Accounting.JournalEntry,
        where: je.reference == ^reference,
        preload: :journal_lines
      )

      debit_line = Enum.find(entry.journal_lines, &(&1.debit_cents == 80_000))
      credit_line = Enum.find(entry.journal_lines, &(&1.credit_cents == 80_000))

      assert debit_line.account_id == expense.expense_account_id
      assert credit_line.account_id == expense.paid_from_account_id
    end

    test "returns error changeset for missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Expenses.create_expense_with_journal(%{})
    end

    test "returns error for zero amount" do
      assert {:error, _} = Expenses.create_expense_with_journal(expense_attrs(%{amount_cents: 0}))
    end

    test "returns error for negative amount" do
      assert {:error, _} = Expenses.create_expense_with_journal(expense_attrs(%{amount_cents: -100}))
    end

    test "returns error for invalid currency" do
      assert {:error, _} = Expenses.create_expense_with_journal(expense_attrs(%{currency: "EUR"}))
    end

    test "accepts USD currency" do
      assert {:ok, expense} = Expenses.create_expense_with_journal(
        expense_attrs(%{currency: "USD", paid_from_account_id: usd_checking_account().id})
      )
      assert expense.currency == "USD"
    end
  end

  # ── update_expense_with_journal/2 ───────────────────────────────────────

  describe "update_expense_with_journal/2" do
    test "updates expense fields" do
      expense = expense_fixture()
      assert {:ok, updated} = Expenses.update_expense_with_journal(expense, %{description: "Updated desc"})
      assert updated.description == "Updated desc"
    end

    test "updates amount and refreshes journal entry lines" do
      expense = expense_fixture(%{amount_cents: 10_000})
      assert {:ok, updated} = Expenses.update_expense_with_journal(expense, %{amount_cents: 25_000})
      assert updated.amount_cents == 25_000

      reference = "Expense ##{expense.id}"
      entry = Repo.one(from je in Ledgr.Core.Accounting.JournalEntry,
        where: je.reference == ^reference,
        preload: :journal_lines
      )
      assert Enum.any?(entry.journal_lines, &(&1.debit_cents == 25_000))
    end

    test "updates expense account" do
      expense = expense_fixture()
      food = food_account()
      assert {:ok, updated} = Expenses.update_expense_with_journal(expense, %{expense_account_id: food.id})
      assert updated.expense_account_id == food.id
    end

    test "returns error changeset for invalid attrs" do
      expense = expense_fixture()
      assert {:error, _} = Expenses.update_expense_with_journal(expense, %{amount_cents: 0})
    end
  end

  # ── delete_expense/1 ────────────────────────────────────────────────────

  describe "delete_expense/1" do
    test "removes the expense record" do
      expense = expense_fixture()
      {:ok, _} = Expenses.delete_expense(expense)
      assert_raise Ecto.NoResultsError, fn -> Expenses.get_expense!(expense.id) end
    end

    test "removes the expense from list_expenses" do
      expense = expense_fixture()
      {:ok, _} = Expenses.delete_expense(expense)
      refute Enum.any?(Expenses.list_expenses(), &(&1.id == expense.id))
    end

    test "deletes the associated journal entry" do
      expense = expense_fixture()
      reference = "Expense ##{expense.id}"
      {:ok, _} = Expenses.delete_expense(expense)

      count = Repo.aggregate(
        from(je in Ledgr.Core.Accounting.JournalEntry, where: je.reference == ^reference),
        :count
      )
      assert count == 0
    end

    test "succeeds even when no journal entry exists" do
      # Insert directly, bypassing journal creation
      attrs = expense_attrs() |> Map.put(:paid_from_account_id, mxn_cash_account().id)
      expense = %Expense{} |> Expense.changeset(attrs) |> Repo.insert!()
      assert {:ok, _} = Expenses.delete_expense(expense)
    end
  end

  # ── total_by_currency/2 ─────────────────────────────────────────────────

  describe "total_by_currency/2" do
    test "returns totals grouped by currency" do
      expense_fixture(%{currency: "MXN", amount_cents: 100_000})
      expense_fixture(%{currency: "MXN", amount_cents: 50_000})
      usd_cash = Accounting.get_account_by_code!("1010")
      expense_fixture(%{currency: "USD", amount_cents: 20_000, paid_from_account_id: usd_cash.id})

      totals = Expenses.total_by_currency(~D[2026-01-01], ~D[2026-12-31])
      assert totals.mxn == 150_000
      assert totals.usd == 20_000
    end

    test "returns zeros when no expenses in range" do
      expense_fixture(%{date: ~D[2026-01-05]})
      totals = Expenses.total_by_currency(~D[2025-01-01], ~D[2025-12-31])
      assert totals.mxn == 0
      assert totals.usd == 0
    end

    test "correctly excludes expenses outside date range" do
      expense_fixture(%{date: ~D[2026-01-10], amount_cents: 30_000, currency: "MXN"})
      expense_fixture(%{date: ~D[2026-03-10], amount_cents: 70_000, currency: "MXN"})

      totals = Expenses.total_by_currency(~D[2026-01-01], ~D[2026-01-31])
      assert totals.mxn == 30_000
    end
  end

  # ── totals_by_account_and_currency/2 ───────────────────────────────────

  describe "totals_by_account_and_currency/2" do
    test "returns rows with account info and totals" do
      expense_fixture(%{amount_cents: 60_000, currency: "MXN"})

      rows = Expenses.totals_by_account_and_currency(~D[2026-01-01], ~D[2026-12-31])
      assert length(rows) >= 1

      row = Enum.find(rows, &(&1.account_code == "6000"))
      assert row != nil
      assert row.total_cents >= 60_000
      assert row.currency == "MXN"
    end

    test "returns empty list when no expenses in range" do
      expense_fixture(%{date: ~D[2026-01-05]})
      assert Expenses.totals_by_account_and_currency(~D[2025-01-01], ~D[2025-12-31]) == []
    end
  end
end
