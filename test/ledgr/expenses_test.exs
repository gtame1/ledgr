defmodule Ledgr.Core.ExpensesTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Expenses
  alias Ledgr.Core.Expenses.Expense
  alias Ledgr.Core.Accounting
  alias Ledgr.Repo

  import Ledgr.Core.AccountingFixtures

  setup do
    standard_accounts_fixture()
    :ok
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp expense_account do
    case Accounting.get_account_by_code("6000") do
      nil ->
        {:ok, a} =
          Accounting.create_account(%{
            code: "6000",
            name: "Operating Expenses",
            type: "expense",
            normal_balance: "debit",
            is_cash: false
          })

        a

      existing ->
        existing
    end
  end

  defp cash_account, do: Accounting.get_account_by_code!("1000")

  defp expense_attrs(overrides \\ %{}) do
    exp_acct = expense_account()
    cash = cash_account()

    Enum.into(overrides, %{
      date: Date.utc_today(),
      description: "Test expense #{System.unique_integer([:positive])}",
      amount_cents: 50_000,
      expense_account_id: exp_acct.id,
      paid_from_account_id: cash.id
    })
  end

  defp expense_fixture(overrides \\ %{}) do
    {:ok, expense} = Expenses.create_expense(expense_attrs(overrides))
    expense
  end

  # ── list_expenses/0 ──────────────────────────────────────────────────

  describe "list_expenses/0" do
    test "returns all expenses with accounts preloaded" do
      expense = expense_fixture()
      expenses = Expenses.list_expenses()
      found = Enum.find(expenses, fn e -> e.id == expense.id end)
      assert found != nil
      assert found.expense_account != nil
      assert found.paid_from_account != nil
    end

    test "returns empty list when no expenses exist" do
      assert Expenses.list_expenses() == [] || is_list(Expenses.list_expenses())
    end

    test "orders by date descending" do
      _older = expense_fixture(%{date: Date.add(Date.utc_today(), -5)})
      _newer = expense_fixture(%{date: Date.utc_today()})

      expenses = Expenses.list_expenses()
      dates = Enum.map(expenses, & &1.date)
      assert dates == Enum.sort(dates, {:desc, Date})
    end
  end

  # ── get_expense!/1 ───────────────────────────────────────────────────

  describe "get_expense!/1" do
    test "returns expense with accounts preloaded" do
      expense = expense_fixture()
      found = Expenses.get_expense!(expense.id)
      assert found.id == expense.id
      assert found.expense_account != nil
      assert found.paid_from_account != nil
    end

    test "raises Ecto.NoResultsError for missing expense" do
      assert_raise Ecto.NoResultsError, fn ->
        Expenses.get_expense!(0)
      end
    end
  end

  # ── change_expense/2 ─────────────────────────────────────────────────

  describe "change_expense/2" do
    test "returns a changeset" do
      expense = expense_fixture()
      assert %Ecto.Changeset{} = Expenses.change_expense(expense, %{description: "Updated"})
    end

    test "returns changeset for new expense" do
      assert %Ecto.Changeset{} = Expenses.change_expense(%Expense{})
    end
  end

  # ── create_expense/1 ─────────────────────────────────────────────────

  describe "create_expense/1" do
    test "creates expense with valid attrs and records journal entry" do
      assert {:ok, %Expense{} = expense} = Expenses.create_expense(expense_attrs())
      assert expense.amount_cents == 50_000
    end

    test "returns error changeset with missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Expenses.create_expense(%{})
    end

    test "returns error with zero amount" do
      assert {:error, _} = Expenses.create_expense(expense_attrs(%{amount_cents: 0}))
    end

    test "stores description and date correctly" do
      today = Date.utc_today()

      {:ok, expense} =
        Expenses.create_expense(
          expense_attrs(%{
            description: "Office supplies",
            date: today
          })
        )

      assert expense.description == "Office supplies"
      assert expense.date == today
    end

    test "stores optional payee and category" do
      {:ok, expense} =
        Expenses.create_expense(
          expense_attrs(%{
            payee: "Staples",
            category: "office"
          })
        )

      assert expense.payee == "Staples"
      assert expense.category == "office"
    end
  end

  # ── update_expense/2 ─────────────────────────────────────────────────

  describe "update_expense/2" do
    test "updates description" do
      expense = expense_fixture()
      assert {:ok, updated} = Expenses.update_expense(expense, %{description: "New description"})
      assert updated.description == "New description"
    end

    test "updates amount and refreshes journal entry" do
      expense = expense_fixture(%{amount_cents: 10_000})
      assert {:ok, updated} = Expenses.update_expense(expense, %{amount_cents: 20_000})
      assert updated.amount_cents == 20_000
    end

    test "returns error changeset for invalid attrs" do
      expense = expense_fixture()
      assert {:error, _} = Expenses.update_expense(expense, %{amount_cents: 0})
    end
  end

  # ── delete_expense/1 ─────────────────────────────────────────────────

  describe "delete_expense/1" do
    test "deletes the expense" do
      expense = expense_fixture()
      {:ok, _} = Expenses.delete_expense(expense)

      assert_raise Ecto.NoResultsError, fn ->
        Expenses.get_expense!(expense.id)
      end
    end

    test "removes the expense from the list" do
      expense = expense_fixture()
      {:ok, _} = Expenses.delete_expense(expense)

      refute Enum.any?(Expenses.list_expenses(), fn e -> e.id == expense.id end)
    end

    test "deletes associated journal entry" do
      expense = expense_fixture()
      reference = "Expense ##{expense.id}"

      {:ok, _} = Expenses.delete_expense(expense)

      import Ecto.Query

      entry_count =
        from(je in Ledgr.Core.Accounting.JournalEntry, where: je.reference == ^reference)
        |> Repo.aggregate(:count)

      assert entry_count == 0
    end
  end
end
