defmodule Ledgr.Core.IvaAccountingTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Expenses
  alias Ledgr.Repo

  import Ledgr.Core.AccountingFixtures

  setup do
    accounts = standard_accounts_fixture()

    # Ensure IVA-related accounts exist
    iva_receivable =
      case Accounting.get_account_by_code("1400") do
        nil ->
          {:ok, acc} =
            Accounting.create_account(%{
              code: "1400",
              name: "IVA Receivable",
              type: "asset",
              normal_balance: "debit",
              is_cash: false
            })

          acc

        existing ->
          existing
      end

    sales_tax_payable =
      case Accounting.get_account_by_code("2100") do
        nil ->
          {:ok, acc} =
            Accounting.create_account(%{
              code: "2100",
              name: "Sales Tax Payable",
              type: "liability",
              normal_balance: "credit",
              is_cash: false
            })

          acc

        existing ->
          existing
      end

    # Create a generic expense account for tests
    {:ok, expense_acc} =
      Accounting.create_account(%{
        code: "IVA_EXP_#{System.unique_integer([:positive])}",
        name: "IVA Test Expense Account",
        type: "expense",
        normal_balance: "debit",
        is_cash: false
      })

    %{
      accounts: accounts,
      iva_receivable: iva_receivable,
      sales_tax_payable: sales_tax_payable,
      expense_acc: expense_acc
    }
  end

  describe "record_expense/1 with IVA splitting" do
    test "expense without IVA creates 2-line entry", %{
      accounts: accounts,
      expense_acc: expense_acc
    } do
      cash = accounts["1000"]

      {:ok, expense} =
        Expenses.create_expense(%{
          date: ~D[2026-01-10],
          description: "Office supplies (no IVA)",
          amount_cents: 5_000,
          iva_cents: 0,
          expense_account_id: expense_acc.id,
          paid_from_account_id: cash.id
        })

      # The expense creates a journal entry via Accounting.record_expense
      entry =
        Repo.get_by!(Accounting.JournalEntry, reference: "Expense ##{expense.id}")
        |> Repo.preload(:journal_lines)

      assert entry.entry_type == "expense"
      assert length(entry.journal_lines) == 2

      debit_line = Enum.find(entry.journal_lines, &(&1.debit_cents > 0))
      credit_line = Enum.find(entry.journal_lines, &(&1.credit_cents > 0))

      assert debit_line.account_id == expense_acc.id
      assert debit_line.debit_cents == 5_000
      assert credit_line.account_id == cash.id
      assert credit_line.credit_cents == 5_000
    end

    test "expense with IVA creates 3-line entry splitting net + IVA", %{
      accounts: accounts,
      expense_acc: expense_acc,
      iva_receivable: iva_receivable
    } do
      cash = accounts["1000"]

      # Total = 11_600 (net 10_000 + IVA 1_600 at 16%)
      {:ok, expense} =
        Expenses.create_expense(%{
          date: ~D[2026-01-15],
          description: "Kitchen gas with IVA",
          amount_cents: 11_600,
          iva_cents: 1_600,
          expense_account_id: expense_acc.id,
          paid_from_account_id: cash.id
        })

      entry =
        Repo.get_by!(Accounting.JournalEntry, reference: "Expense ##{expense.id}")
        |> Repo.preload(:journal_lines)

      assert length(entry.journal_lines) == 3

      # Net expense debit
      expense_line = Enum.find(entry.journal_lines, &(&1.account_id == expense_acc.id))
      assert expense_line.debit_cents == 10_000

      # IVA receivable debit
      iva_line = Enum.find(entry.journal_lines, &(&1.account_id == iva_receivable.id))
      assert iva_line.debit_cents == 1_600

      # Cash credit for full amount
      cash_line = Enum.find(entry.journal_lines, &(&1.account_id == cash.id))
      assert cash_line.credit_cents == 11_600

      # Entry must balance
      total_debits = Enum.reduce(entry.journal_lines, 0, &(&1.debit_cents + &2))
      total_credits = Enum.reduce(entry.journal_lines, 0, &(&1.credit_cents + &2))
      assert total_debits == total_credits
    end

    test "expense with nil iva_cents treated as zero IVA", %{
      accounts: accounts,
      expense_acc: expense_acc
    } do
      cash = accounts["1000"]

      {:ok, expense} =
        Expenses.create_expense(%{
          date: ~D[2026-02-01],
          description: "Food (zero-rated)",
          amount_cents: 3_000,
          expense_account_id: expense_acc.id,
          paid_from_account_id: cash.id
        })

      entry =
        Repo.get_by!(Accounting.JournalEntry, reference: "Expense ##{expense.id}")
        |> Repo.preload(:journal_lines)

      # No IVA line - only 2 lines
      assert length(entry.journal_lines) == 2
    end
  end

  describe "iva_position/1" do
    test "returns zero when no IVA transactions exist" do
      position = Accounting.iva_position(~D[2026-01-01])

      assert position.iva_receivable_cents == 0
      assert position.iva_payable_cents == 0
      assert position.net_position_cents == 0
      assert position.as_of_date == ~D[2026-01-01]
    end

    test "tracks IVA receivable from expenses", %{
      accounts: accounts,
      expense_acc: expense_acc,
      iva_receivable: iva_receivable
    } do
      cash = accounts["1000"]

      # Two expenses with IVA
      {:ok, _} =
        Expenses.create_expense(%{
          date: ~D[2026-03-01],
          description: "Expense A",
          amount_cents: 11_600,
          iva_cents: 1_600,
          expense_account_id: expense_acc.id,
          paid_from_account_id: cash.id
        })

      {:ok, _} =
        Expenses.create_expense(%{
          date: ~D[2026-03-15],
          description: "Expense B",
          amount_cents: 5_800,
          iva_cents: 800,
          expense_account_id: expense_acc.id,
          paid_from_account_id: cash.id
        })

      position = Accounting.iva_position(~D[2026-03-31])
      assert position.iva_receivable_cents == 2_400
      assert position.iva_payable_cents == 0
      assert position.net_position_cents == 2_400
    end

    test "tracks IVA payable from sales", %{
      accounts: accounts,
      sales_tax_payable: sales_tax_payable
    } do
      cash = accounts["1000"]

      # Simulate a sale with IVA collected: Dr Cash, Cr Revenue, Cr Sales Tax Payable
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2026-04-10],
            entry_type: "sale",
            reference: "iva-sale-1",
            description: "Sale with IVA"
          },
          [
            %{
              account_id: cash.id,
              debit_cents: 11_600,
              credit_cents: 0,
              description: "cash received"
            },
            %{
              account_id: accounts["4000"].id,
              debit_cents: 0,
              credit_cents: 10_000,
              description: "revenue"
            },
            %{
              account_id: sales_tax_payable.id,
              debit_cents: 0,
              credit_cents: 1_600,
              description: "IVA collected"
            }
          ]
        )

      position = Accounting.iva_position(~D[2026-04-30])
      assert position.iva_payable_cents == 1_600
      assert position.net_position_cents == -1_600
    end

    test "computes net position (receivable minus payable)", %{
      accounts: accounts,
      expense_acc: expense_acc,
      sales_tax_payable: sales_tax_payable
    } do
      cash = accounts["1000"]

      # IVA paid on expense: 1_600
      {:ok, _} =
        Expenses.create_expense(%{
          date: ~D[2026-05-01],
          description: "Purchase with IVA",
          amount_cents: 11_600,
          iva_cents: 1_600,
          expense_account_id: expense_acc.id,
          paid_from_account_id: cash.id
        })

      # IVA collected on sale: 2_400
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2026-05-15],
            entry_type: "sale",
            reference: "iva-net-1",
            description: "Sale"
          },
          [
            %{account_id: cash.id, debit_cents: 17_400, credit_cents: 0, description: "cash"},
            %{
              account_id: accounts["4000"].id,
              debit_cents: 0,
              credit_cents: 15_000,
              description: "rev"
            },
            %{
              account_id: sales_tax_payable.id,
              debit_cents: 0,
              credit_cents: 2_400,
              description: "iva"
            }
          ]
        )

      position = Accounting.iva_position(~D[2026-05-31])
      assert position.iva_receivable_cents == 1_600
      assert position.iva_payable_cents == 2_400
      # Net = 1600 - 2400 = -800 (owes 800 to tax authority)
      assert position.net_position_cents == -800
    end

    test "respects the as_of_date cutoff", %{accounts: accounts, expense_acc: expense_acc} do
      cash = accounts["1000"]

      # Expense in January
      {:ok, _} =
        Expenses.create_expense(%{
          date: ~D[2026-01-10],
          description: "Jan expense",
          amount_cents: 5_800,
          iva_cents: 800,
          expense_account_id: expense_acc.id,
          paid_from_account_id: cash.id
        })

      # Expense in March
      {:ok, _} =
        Expenses.create_expense(%{
          date: ~D[2026-03-10],
          description: "Mar expense",
          amount_cents: 11_600,
          iva_cents: 1_600,
          expense_account_id: expense_acc.id,
          paid_from_account_id: cash.id
        })

      # As of January 31: only Jan IVA
      jan_position = Accounting.iva_position(~D[2026-01-31])
      assert jan_position.iva_receivable_cents == 800

      # As of March 31: both
      mar_position = Accounting.iva_position(~D[2026-03-31])
      assert mar_position.iva_receivable_cents == 2_400
    end
  end
end
