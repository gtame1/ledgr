defmodule Ledgr.Core.BudgetsTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Budgets
  alias Ledgr.Core.Budgets.Budget
  alias Ledgr.Core.Accounting

  import Ledgr.Core.AccountingFixtures

  setup do
    accounts = standard_accounts_fixture()
    %{accounts: accounts}
  end

  describe "CRUD" do
    test "create_budget/1 with valid data", %{accounts: accounts} do
      cash = accounts["1000"]

      assert {:ok, %Budget{} = budget} =
               Budgets.create_budget(%{
                 year: 2026,
                 month: 1,
                 amount_cents: 50_000,
                 account_id: cash.id
               })

      assert budget.year == 2026
      assert budget.month == 1
      assert budget.amount_cents == 50_000
      assert budget.account_id == cash.id
    end

    test "create_budget/1 rejects invalid month" do
      assert {:error, changeset} =
               Budgets.create_budget(%{year: 2026, month: 13, amount_cents: 100, account_id: 1})

      assert %{month: _} = errors_on(changeset)
    end

    test "create_budget/1 rejects negative amount", %{accounts: accounts} do
      assert {:error, changeset} =
               Budgets.create_budget(%{
                 year: 2026,
                 month: 1,
                 amount_cents: -100,
                 account_id: accounts["1000"].id
               })

      assert %{amount_cents: _} = errors_on(changeset)
    end

    test "update_budget/2 changes the amount", %{accounts: accounts} do
      {:ok, budget} =
        Budgets.create_budget(%{
          year: 2026,
          month: 2,
          amount_cents: 10_000,
          account_id: accounts["1000"].id
        })

      assert {:ok, updated} = Budgets.update_budget(budget, %{amount_cents: 20_000})
      assert updated.amount_cents == 20_000
    end

    test "delete_budget/1 removes the budget", %{accounts: accounts} do
      {:ok, budget} =
        Budgets.create_budget(%{
          year: 2026,
          month: 3,
          amount_cents: 5_000,
          account_id: accounts["1000"].id
        })

      assert {:ok, _} = Budgets.delete_budget(budget)
      assert_raise Ecto.NoResultsError, fn -> Budgets.get_budget!(budget.id) end
    end

    test "upsert_budget/1 creates then updates on conflict", %{accounts: accounts} do
      cash = accounts["1000"]

      {:ok, b1} =
        Budgets.upsert_budget(%{year: 2026, month: 4, amount_cents: 1_000, account_id: cash.id})

      assert b1.amount_cents == 1_000

      {:ok, b2} =
        Budgets.upsert_budget(%{year: 2026, month: 4, amount_cents: 2_000, account_id: cash.id})

      assert b2.id == b1.id
      assert b2.amount_cents == 2_000
    end

    test "list_budgets/2 returns budgets for year/month", %{accounts: accounts} do
      cash = accounts["1000"]
      ar = accounts["1100"]

      {:ok, _} =
        Budgets.create_budget(%{year: 2026, month: 5, amount_cents: 100, account_id: cash.id})

      {:ok, _} =
        Budgets.create_budget(%{year: 2026, month: 5, amount_cents: 200, account_id: ar.id})

      {:ok, _} =
        Budgets.create_budget(%{year: 2026, month: 6, amount_cents: 300, account_id: cash.id})

      result = Budgets.list_budgets(2026, 5)
      assert length(result) == 2
    end

    test "set_monthly_budgets/3 bulk upserts", %{accounts: accounts} do
      cash = accounts["1000"]
      ar = accounts["1100"]

      items = [
        %{account_id: cash.id, amount_cents: 1_000},
        %{account_id: ar.id, amount_cents: 2_000}
      ]

      results = Budgets.set_monthly_budgets(2026, 7, items)
      assert length(results) == 2

      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)

      budgets = Budgets.list_budgets(2026, 7)
      assert length(budgets) == 2
    end
  end

  describe "budget_vs_actual/2" do
    test "returns empty report when no budgets exist" do
      report = Budgets.budget_vs_actual(2026, 1)
      assert report.line_items == []
      assert report.net_budget_cents == 0
      assert report.net_actual_cents == 0
    end

    test "computes variance for an expense account", %{accounts: accounts} do
      # Create an expense account and budget it
      {:ok, expense_acc} =
        Accounting.create_account(%{
          code: "BVA_EXP1",
          name: "BVA Test Expense",
          type: "expense",
          normal_balance: "debit",
          is_cash: false
        })

      cash = accounts["1000"]

      {:ok, _} =
        Budgets.create_budget(%{
          year: 2026,
          month: 1,
          amount_cents: 10_000,
          account_id: expense_acc.id
        })

      # Record some actual spending: Dr expense 7500, Cr cash 7500
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2026-01-15],
            entry_type: "expense",
            reference: "bva-test-1",
            description: "test"
          },
          [
            %{
              account_id: expense_acc.id,
              debit_cents: 7_500,
              credit_cents: 0,
              description: "exp"
            },
            %{account_id: cash.id, debit_cents: 0, credit_cents: 7_500, description: "paid"}
          ]
        )

      report = Budgets.budget_vs_actual(2026, 1)
      assert length(report.line_items) == 1

      item = hd(report.line_items)
      assert item.budget_cents == 10_000
      assert item.actual_cents == 7_500
      assert item.variance_cents == -2_500
      assert item.account_type == "expense"

      assert report.total_budget_expense_cents == 10_000
      assert report.total_actual_expense_cents == 7_500
    end

    test "computes variance for a revenue account", %{accounts: accounts} do
      revenue_acc = accounts["4000"]
      cash = accounts["1000"]

      {:ok, _} =
        Budgets.create_budget(%{
          year: 2026,
          month: 2,
          amount_cents: 50_000,
          account_id: revenue_acc.id
        })

      # Record actual revenue: Dr cash 60_000, Cr revenue 60_000
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2026-02-10],
            entry_type: "sale",
            reference: "bva-rev-1",
            description: "test sale"
          },
          [
            %{account_id: cash.id, debit_cents: 60_000, credit_cents: 0, description: "cash"},
            %{
              account_id: revenue_acc.id,
              debit_cents: 0,
              credit_cents: 60_000,
              description: "rev"
            }
          ]
        )

      report = Budgets.budget_vs_actual(2026, 2)

      item = hd(report.line_items)
      # Revenue: actual = credits - debits = 60_000 (normalized to positive)
      assert item.actual_cents == 60_000
      assert item.budget_cents == 50_000
      assert item.variance_cents == 10_000

      assert report.total_budget_revenue_cents == 50_000
      assert report.total_actual_revenue_cents == 60_000
    end

    test "excludes journal entries outside the target month", %{accounts: accounts} do
      {:ok, expense_acc} =
        Accounting.create_account(%{
          code: "BVA_EXP2",
          name: "BVA Exp 2",
          type: "expense",
          normal_balance: "debit",
          is_cash: false
        })

      cash = accounts["1000"]

      {:ok, _} =
        Budgets.create_budget(%{
          year: 2026,
          month: 3,
          amount_cents: 10_000,
          account_id: expense_acc.id
        })

      # Entry in February (should NOT count)
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2026-02-28],
            entry_type: "expense",
            reference: "bva-feb",
            description: "feb"
          },
          [
            %{
              account_id: expense_acc.id,
              debit_cents: 5_000,
              credit_cents: 0,
              description: "exp"
            },
            %{account_id: cash.id, debit_cents: 0, credit_cents: 5_000, description: "paid"}
          ]
        )

      # Entry in March (should count)
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2026-03-15],
            entry_type: "expense",
            reference: "bva-mar",
            description: "mar"
          },
          [
            %{
              account_id: expense_acc.id,
              debit_cents: 3_000,
              credit_cents: 0,
              description: "exp"
            },
            %{account_id: cash.id, debit_cents: 0, credit_cents: 3_000, description: "paid"}
          ]
        )

      report = Budgets.budget_vs_actual(2026, 3)
      item = hd(report.line_items)
      assert item.actual_cents == 3_000
    end

    test "net_budget and net_actual compute revenue minus expenses", %{accounts: accounts} do
      revenue_acc = accounts["4000"]
      cash = accounts["1000"]

      {:ok, expense_acc} =
        Accounting.create_account(%{
          code: "BVA_NET",
          name: "BVA Net Exp",
          type: "expense",
          normal_balance: "debit",
          is_cash: false
        })

      {:ok, _} =
        Budgets.create_budget(%{
          year: 2026,
          month: 4,
          amount_cents: 20_000,
          account_id: revenue_acc.id
        })

      {:ok, _} =
        Budgets.create_budget(%{
          year: 2026,
          month: 4,
          amount_cents: 8_000,
          account_id: expense_acc.id
        })

      # Revenue: 25_000
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{date: ~D[2026-04-10], entry_type: "sale", reference: "bva-net-r", description: "rev"},
          [
            %{account_id: cash.id, debit_cents: 25_000, credit_cents: 0, description: "cash"},
            %{
              account_id: revenue_acc.id,
              debit_cents: 0,
              credit_cents: 25_000,
              description: "rev"
            }
          ]
        )

      # Expense: 6_000
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2026-04-15],
            entry_type: "expense",
            reference: "bva-net-e",
            description: "exp"
          },
          [
            %{
              account_id: expense_acc.id,
              debit_cents: 6_000,
              credit_cents: 0,
              description: "exp"
            },
            %{account_id: cash.id, debit_cents: 0, credit_cents: 6_000, description: "paid"}
          ]
        )

      report = Budgets.budget_vs_actual(2026, 4)
      assert report.net_budget_cents == 20_000 - 8_000
      assert report.net_actual_cents == 25_000 - 6_000
    end
  end

  describe "budget_vs_actual_ytd/2" do
    test "aggregates budgets across multiple months", %{accounts: accounts} do
      {:ok, expense_acc} =
        Accounting.create_account(%{
          code: "BVA_YTD1",
          name: "YTD Test Exp",
          type: "expense",
          normal_balance: "debit",
          is_cash: false
        })

      cash = accounts["1000"]

      # Budget: Jan=5000, Feb=6000, Mar=7000
      {:ok, _} =
        Budgets.create_budget(%{
          year: 2026,
          month: 1,
          amount_cents: 5_000,
          account_id: expense_acc.id
        })

      {:ok, _} =
        Budgets.create_budget(%{
          year: 2026,
          month: 2,
          amount_cents: 6_000,
          account_id: expense_acc.id
        })

      {:ok, _} =
        Budgets.create_budget(%{
          year: 2026,
          month: 3,
          amount_cents: 7_000,
          account_id: expense_acc.id
        })

      # Actuals: Jan=4000, Feb=5500
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2026-01-15],
            entry_type: "expense",
            reference: "ytd-jan",
            description: "jan"
          },
          [
            %{
              account_id: expense_acc.id,
              debit_cents: 4_000,
              credit_cents: 0,
              description: "exp"
            },
            %{account_id: cash.id, debit_cents: 0, credit_cents: 4_000, description: "paid"}
          ]
        )

      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2026-02-10],
            entry_type: "expense",
            reference: "ytd-feb",
            description: "feb"
          },
          [
            %{
              account_id: expense_acc.id,
              debit_cents: 5_500,
              credit_cents: 0,
              description: "exp"
            },
            %{account_id: cash.id, debit_cents: 0, credit_cents: 5_500, description: "paid"}
          ]
        )

      # YTD through Feb: budget = 5000+6000 = 11000, actual = 4000+5500 = 9500
      report = Budgets.budget_vs_actual_ytd(2026, 2)

      assert length(report.line_items) == 1
      item = hd(report.line_items)
      assert item.budget_cents == 11_000
      assert item.actual_cents == 9_500
      assert item.variance_cents == -1_500
    end

    test "returns empty report when no budgets exist" do
      report = Budgets.budget_vs_actual_ytd(2026, 6)
      assert report.line_items == []
    end
  end
end
