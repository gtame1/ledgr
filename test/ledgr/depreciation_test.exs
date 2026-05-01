defmodule Ledgr.Core.DepreciationTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Accounting
  alias Ledgr.Repo

  import Ledgr.Core.AccountingFixtures

  setup do
    accounts = standard_accounts_fixture()

    # Ensure depreciation-related accounts exist
    depreciation_expense =
      case Accounting.get_account_by_code("6045") do
        nil ->
          {:ok, acc} =
            Accounting.create_account(%{
              code: "6045",
              name: "Depreciation Expense",
              type: "expense",
              normal_balance: "debit",
              is_cash: false
            })

          acc

        existing ->
          existing
      end

    accum_depreciation =
      case Accounting.get_account_by_code("1310") do
        nil ->
          {:ok, acc} =
            Accounting.create_account(%{
              code: "1310",
              name: "Accumulated Depreciation",
              type: "asset",
              normal_balance: "credit",
              is_cash: false
            })

          acc

        existing ->
          existing
      end

    kitchen_equipment =
      case Accounting.get_account_by_code("1300") do
        nil ->
          {:ok, acc} =
            Accounting.create_account(%{
              code: "1300",
              name: "Kitchen Equipment",
              type: "asset",
              normal_balance: "debit",
              is_cash: false
            })

          acc

        existing ->
          existing
      end

    %{
      accounts: accounts,
      depreciation_expense: depreciation_expense,
      accum_depreciation: accum_depreciation,
      kitchen_equipment: kitchen_equipment
    }
  end

  describe "record_depreciation/2" do
    test "creates a journal entry with correct debits and credits", %{
      depreciation_expense: dep_exp,
      accum_depreciation: accum_dep
    } do
      {:ok, entry} = Accounting.record_depreciation(5_000, date: ~D[2026-01-31])

      entry = Repo.preload(entry, :journal_lines)

      assert entry.entry_type == "depreciation"
      assert entry.date == ~D[2026-01-31]
      assert length(entry.journal_lines) == 2

      debit_line = Enum.find(entry.journal_lines, &(&1.debit_cents > 0))
      credit_line = Enum.find(entry.journal_lines, &(&1.credit_cents > 0))

      assert debit_line.account_id == dep_exp.id
      assert debit_line.debit_cents == 5_000
      assert credit_line.account_id == accum_dep.id
      assert credit_line.credit_cents == 5_000
    end

    test "uses default date, reference, and description when not provided", %{} do
      {:ok, entry} = Accounting.record_depreciation(3_000)

      assert entry.date == Date.utc_today()
      assert entry.reference == "Monthly depreciation"
      assert entry.description == "Monthly straight-line depreciation - Kitchen Equipment"
    end

    test "allows custom reference and description", %{} do
      {:ok, entry} =
        Accounting.record_depreciation(2_000,
          date: ~D[2026-06-30],
          reference: "H1 2026 Depreciation",
          description: "Half-year depreciation for blender"
        )

      assert entry.reference == "H1 2026 Depreciation"
      assert entry.description == "Half-year depreciation for blender"
    end

    test "entry balances (total debits == total credits)", %{} do
      {:ok, entry} = Accounting.record_depreciation(12_345)
      entry = Repo.preload(entry, :journal_lines)

      total_debits = Enum.reduce(entry.journal_lines, 0, &(&1.debit_cents + &2))
      total_credits = Enum.reduce(entry.journal_lines, 0, &(&1.credit_cents + &2))

      assert total_debits == total_credits
      assert total_debits == 12_345
    end
  end

  describe "calculate_monthly_depreciation/1" do
    test "returns 0 when no equipment exists", %{} do
      assert Accounting.calculate_monthly_depreciation(60) == 0
    end

    test "calculates straight-line depreciation from gross cost", %{
      accounts: accounts,
      kitchen_equipment: kitchen_eq
    } do
      cash = accounts["1000"]

      # Purchase kitchen equipment for 120_000 cents ($1,200)
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2026-01-01],
            entry_type: "inventory_purchase",
            reference: "equip-buy",
            description: "Oven"
          },
          [
            %{
              account_id: kitchen_eq.id,
              debit_cents: 120_000,
              credit_cents: 0,
              description: "equipment"
            },
            %{account_id: cash.id, debit_cents: 0, credit_cents: 120_000, description: "paid"}
          ]
        )

      # 60-month useful life: monthly depreciation = 120_000 / 60 = 2_000
      assert Accounting.calculate_monthly_depreciation(60) == 2_000
    end

    test "returns 0 when equipment is fully depreciated", %{
      accounts: accounts,
      kitchen_equipment: kitchen_eq,
      accum_depreciation: accum_dep
    } do
      cash = accounts["1000"]

      # Purchase for 60_000
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2025-01-01],
            entry_type: "inventory_purchase",
            reference: "equip-full",
            description: "Mixer"
          },
          [
            %{
              account_id: kitchen_eq.id,
              debit_cents: 60_000,
              credit_cents: 0,
              description: "equip"
            },
            %{account_id: cash.id, debit_cents: 0, credit_cents: 60_000, description: "paid"}
          ]
        )

      dep_exp =
        case Accounting.get_account_by_code("6045") do
          nil -> raise "6045 should exist"
          acc -> acc
        end

      # Record full depreciation (60_000 accumulated)
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2025-12-31],
            entry_type: "depreciation",
            reference: "full-dep",
            description: "Full depr"
          },
          [
            %{
              account_id: dep_exp.id,
              debit_cents: 60_000,
              credit_cents: 0,
              description: "dep exp"
            },
            %{
              account_id: accum_dep.id,
              debit_cents: 0,
              credit_cents: 60_000,
              description: "accum dep"
            }
          ]
        )

      # Remaining = 60_000 - 60_000 = 0, so monthly depreciation should be 0
      assert Accounting.calculate_monthly_depreciation(60) == 0
    end

    test "uses gross cost (not net book value) for monthly amount", %{
      accounts: accounts,
      kitchen_equipment: kitchen_eq,
      accum_depreciation: accum_dep
    } do
      cash = accounts["1000"]

      dep_exp =
        case Accounting.get_account_by_code("6045") do
          nil -> raise "6045 should exist"
          acc -> acc
        end

      # Purchase for 120_000
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2025-06-01],
            entry_type: "inventory_purchase",
            reference: "equip-partial",
            description: "Oven"
          },
          [
            %{
              account_id: kitchen_eq.id,
              debit_cents: 120_000,
              credit_cents: 0,
              description: "equip"
            },
            %{account_id: cash.id, debit_cents: 0, credit_cents: 120_000, description: "paid"}
          ]
        )

      # Already depreciated 24_000 (12 months of 2_000)
      {:ok, _} =
        Accounting.create_journal_entry_with_lines(
          %{
            date: ~D[2025-12-31],
            entry_type: "depreciation",
            reference: "past-dep",
            description: "Past"
          },
          [
            %{
              account_id: dep_exp.id,
              debit_cents: 24_000,
              credit_cents: 0,
              description: "dep exp"
            },
            %{
              account_id: accum_dep.id,
              debit_cents: 0,
              credit_cents: 24_000,
              description: "accum dep"
            }
          ]
        )

      # Straight-line uses gross cost / useful life, NOT remaining / remaining life
      # 120_000 / 60 = 2_000 per month (same as before)
      monthly = Accounting.calculate_monthly_depreciation(60)
      assert monthly == 2_000
    end
  end
end
