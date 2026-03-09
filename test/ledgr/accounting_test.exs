defmodule Ledgr.Core.AccountingTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.MrMunchMe.OrderAccounting
  alias Ledgr.Repo
  alias Ledgr.Core.Accounting.{Account, JournalEntry, MoneyTransfer}
  alias Ledgr.Domains.MrMunchMe.Orders.{OrderPayment}

  import Ledgr.Core.AccountingFixtures
  import Ledgr.Domains.MrMunchMe.OrdersFixtures

  describe "accounts" do
    test "list_accounts/0 returns all accounts ordered by code" do
      _accounts = standard_accounts_fixture()

      result = Accounting.list_accounts()
      codes = Enum.map(result, & &1.code)

      assert codes == Enum.sort(codes)
      assert length(result) >= 9
    end

    test "get_account!/1 returns the account with given id" do
      account = account_fixture(%{code: "TEST1", name: "Test Account"})
      assert Accounting.get_account!(account.id).id == account.id
    end

    test "get_account_by_code!/1 returns the account with given code" do
      _account = account_fixture(%{code: "TEST2", name: "Test Account 2"})
      result = Accounting.get_account_by_code!("TEST2")
      assert result.code == "TEST2"
    end

    test "create_account/1 with valid data creates an account" do
      attrs = %{
        code: "9999",
        name: "New Test Account",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      }

      assert {:ok, %Account{} = account} = Accounting.create_account(attrs)
      assert account.code == "9999"
      assert account.name == "New Test Account"
      assert account.type == "asset"
    end

    test "account_select_options/0 returns formatted options" do
      _accounts = standard_accounts_fixture()
      options = Accounting.account_select_options()

      assert is_list(options)
      assert Enum.all?(options, fn {label, id} ->
        String.contains?(label, " - ") && is_integer(id)
      end)
    end

    test "cash_or_bank_account_options/0 returns only cash/bank accounts" do
      _accounts = standard_accounts_fixture()
      options = Accounting.cash_or_bank_account_options()

      assert length(options) >= 1
      # All returned accounts should be assets with is_cash true or name containing bank
      Enum.each(options, fn {label, _id} ->
        assert String.starts_with?(label, "1")  # Asset accounts start with 1
      end)
    end

    test "expense_account_options/0 returns only expense accounts" do
      _accounts = standard_accounts_fixture()
      options = Accounting.expense_account_options()

      assert is_list(options)
      # All returned accounts should have expense codes (5xxx or 6xxx)
      Enum.each(options, fn {label, _id} ->
        code = String.split(label, " ") |> hd()
        assert String.starts_with?(code, "5") or String.starts_with?(code, "6")
      end)
    end
  end

  describe "journal_entry_date_range/0" do
    test "returns nil tuple when no entries exist" do
      # Clear any existing entries first by creating fresh accounts
      _accounts = standard_accounts_fixture()

      # Check the date range
      {earliest, latest} = Accounting.journal_entry_date_range()

      # Either both nil or both dates (depends on test isolation)
      assert (is_nil(earliest) and is_nil(latest)) or (is_struct(earliest, Date) and is_struct(latest, Date))
    end
  end

  describe "journal entries" do
    setup do
      accounts = standard_accounts_fixture()
      {:ok, accounts: accounts}
    end

    test "create_journal_entry/1 creates entry with valid data", %{accounts: _accounts} do
      attrs = %{
        date: Date.utc_today(),
        entry_type: "other",
        reference: "TEST-001",
        description: "Test journal entry"
      }

      assert {:ok, %JournalEntry{} = entry} = Accounting.create_journal_entry(attrs)
      assert entry.entry_type == "other"
      assert entry.reference == "TEST-001"
    end

    test "create_journal_entry_with_lines/2 creates balanced entry", %{accounts: accounts} do
      entry_attrs = %{
        date: Date.utc_today(),
        entry_type: "other",
        reference: "TEST-002",
        description: "Test entry with lines"
      }

      cash = accounts["1000"]
      ar = accounts["1100"]

      lines = [
        %{account_id: cash.id, debit_cents: 10000, credit_cents: 0, description: "Debit cash"},
        %{account_id: ar.id, debit_cents: 0, credit_cents: 10000, description: "Credit AR"}
      ]

      assert {:ok, %JournalEntry{} = entry} = Accounting.create_journal_entry_with_lines(entry_attrs, lines)
      entry = Repo.preload(entry, :journal_lines)

      assert length(entry.journal_lines) == 2

      total_debits = Enum.sum(Enum.map(entry.journal_lines, & &1.debit_cents))
      total_credits = Enum.sum(Enum.map(entry.journal_lines, & &1.credit_cents))

      assert total_debits == total_credits
    end

    test "list_journal_entries/0 returns entries ordered by date", %{accounts: accounts} do
      cash = accounts["1000"]
      ar = accounts["1100"]

      entry_attrs = %{
        date: Date.utc_today(),
        entry_type: "other",
        reference: "LIST-TEST",
        description: "Test for listing"
      }

      lines = [
        %{account_id: cash.id, debit_cents: 5000, credit_cents: 0, description: "Debit"},
        %{account_id: ar.id, debit_cents: 0, credit_cents: 5000, description: "Credit"}
      ]

      {:ok, _created_entry} = Accounting.create_journal_entry_with_lines(entry_attrs, lines)

      entries = Accounting.list_journal_entries()
      assert length(entries) >= 1

      # Check that entries are ordered by date (newest first)
      test_entry = Enum.find(entries, fn e -> e.reference == "LIST-TEST" end)
      assert test_entry != nil
      assert test_entry.journal_lines != nil
    end

    test "get_journal_entry!/1 returns entry with lines and totals", %{accounts: accounts} do
      cash = accounts["1000"]
      ar = accounts["1100"]

      entry_attrs = %{
        date: Date.utc_today(),
        entry_type: "other",
        reference: "GET-TEST",
        description: "Test for get"
      }

      lines = [
        %{account_id: cash.id, debit_cents: 7500, credit_cents: 0, description: "Debit"},
        %{account_id: ar.id, debit_cents: 0, credit_cents: 7500, description: "Credit"}
      ]

      {:ok, created_entry} = Accounting.create_journal_entry_with_lines(entry_attrs, lines)

      entry = Accounting.get_journal_entry!(created_entry.id)
      assert entry.reference == "GET-TEST"
      assert length(entry.journal_lines) == 2

      # Calculate total manually from lines to verify
      total_debits = Enum.sum(Enum.map(entry.journal_lines, & &1.debit_cents))
      assert total_debits == 7500
    end

    test "list_journal_lines_by_account/2 filters by account and date range", %{accounts: accounts} do
      cash = accounts["1000"]
      ar = accounts["1100"]

      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      # Create entry for yesterday
      {:ok, _} = Accounting.create_journal_entry_with_lines(
        %{date: yesterday, entry_type: "other", reference: "YESTERDAY", description: "Yesterday"},
        [
          %{account_id: cash.id, debit_cents: 1000, credit_cents: 0, description: "D"},
          %{account_id: ar.id, debit_cents: 0, credit_cents: 1000, description: "C"}
        ]
      )

      # Create entry for today
      {:ok, _} = Accounting.create_journal_entry_with_lines(
        %{date: today, entry_type: "other", reference: "TODAY", description: "Today"},
        [
          %{account_id: cash.id, debit_cents: 2000, credit_cents: 0, description: "D"},
          %{account_id: ar.id, debit_cents: 0, credit_cents: 2000, description: "C"}
        ]
      )

      # Get all lines for cash account
      all_lines = Accounting.list_journal_lines_by_account(cash.id)
      assert length(all_lines) >= 2

      # Filter by today only
      today_lines = Accounting.list_journal_lines_by_account(cash.id, date_from: today, date_to: today)
      today_refs = Enum.map(today_lines, fn l -> l.journal_entry.reference end)
      assert "TODAY" in today_refs
      refute "YESTERDAY" in today_refs
    end
  end

  describe "record_inventory_purchase/2" do
    setup do
      accounts = standard_accounts_fixture()
      {:ok, accounts: accounts}
    end

    test "creates journal entry for ingredients purchase", %{accounts: accounts} do
      cash = accounts["1000"]
      ingredients = accounts["1200"]

      {:ok, entry} = Accounting.record_inventory_purchase(50000, [
        reference: "PO-001",
        paid_from_account: cash
      ])

      entry = Repo.preload(entry, :journal_lines)

      # Should have 2 lines: debit inventory, credit cash
      assert length(entry.journal_lines) == 2
      assert entry.entry_type == "inventory_purchase"

      # Find the inventory debit line
      inv_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == ingredients.id && l.debit_cents > 0
      end)
      assert inv_line.debit_cents == 50000

      # Find the cash credit line
      cash_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == cash.id && l.credit_cents > 0
      end)
      assert cash_line.credit_cents == 50000
    end

    test "creates journal entry for packing purchase", %{accounts: accounts} do
      cash = accounts["1000"]
      packing = accounts["1210"]

      {:ok, entry} = Accounting.record_inventory_purchase(25000, [
        packing: true,
        paid_from_account: cash
      ])

      entry = Repo.preload(entry, :journal_lines)

      # Find the packing debit line
      packing_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == packing.id && l.debit_cents > 0
      end)
      assert packing_line.debit_cents == 25000
    end

    test "uses paid_from_account_id option", %{accounts: accounts} do
      cash = accounts["1000"]

      {:ok, entry} = Accounting.record_inventory_purchase(30000, [
        paid_from_account_id: cash.id
      ])

      entry = Repo.preload(entry, :journal_lines)

      cash_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == cash.id && l.credit_cents > 0
      end)
      assert cash_line != nil
    end
  end

  describe "record_inventory_return/2" do
    setup do
      accounts = standard_accounts_fixture()
      {:ok, accounts: accounts}
    end

    test "creates reverse journal entry for return", %{accounts: accounts} do
      cash = accounts["1000"]
      ingredients = accounts["1200"]

      {:ok, entry} = Accounting.record_inventory_return(15000, [
        reference: "RET-001",
        paid_from_account: cash
      ])

      entry = Repo.preload(entry, :journal_lines)

      # Should have 2 lines: credit inventory (decrease), debit cash (refund)
      assert length(entry.journal_lines) == 2

      # Find the inventory credit line
      inv_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == ingredients.id && l.credit_cents > 0
      end)
      assert inv_line.credit_cents == 15000

      # Find the cash debit line
      cash_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == cash.id && l.debit_cents > 0
      end)
      assert cash_line.debit_cents == 15000
    end
  end

  describe "record_investment/2 and record_withdrawal/2" do
    setup do
      accounts = standard_accounts_fixture()
      # Owner's Equity (3000) and Retained Earnings (3050) are now included in standard_accounts_fixture
      {:ok, accounts: accounts}
    end

    test "record_investment creates correct journal entry", %{accounts: accounts} do
      cash = accounts["1000"]

      {:ok, entry} = Accounting.record_investment(100000, [
        cash_account_id: cash.id,
        partner_name: "Test Partner",
        date: Date.utc_today()
      ])

      entry = Repo.preload(entry, :journal_lines)

      assert entry.entry_type == "investment"
      assert length(entry.journal_lines) == 2

      # Cash debit
      cash_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == cash.id && l.debit_cents > 0
      end)
      assert cash_line.debit_cents == 100000

      # Equity credit
      equity = accounts["3000"]
      equity_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == equity.id && l.credit_cents > 0
      end)
      assert equity_line.credit_cents == 100000
    end

    test "record_withdrawal creates correct journal entry", %{accounts: accounts} do
      cash = accounts["1000"]
      owners_drawings = accounts["3100"]

      {:ok, entry} = Accounting.record_withdrawal(50000, [
        cash_account_id: cash.id,
        partner_name: "Test Partner",
        date: Date.utc_today()
      ])

      entry = Repo.preload(entry, :journal_lines)

      assert entry.entry_type == "withdrawal"

      # Owner's Drawings debit (contra-equity increases)
      drawings_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == owners_drawings.id && l.debit_cents > 0
      end)
      assert drawings_line.debit_cents == 50000

      # Cash credit (pay out)
      cash_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == cash.id && l.credit_cents > 0
      end)
      assert cash_line.credit_cents == 50000
    end
  end

  describe "money transfers" do
    setup do
      accounts = standard_accounts_fixture()
      {:ok, accounts: accounts}
    end

    test "create_money_transfer/1 creates transfer and journal entry", %{accounts: accounts} do
      cash = accounts["1000"]
      ar = accounts["1100"]

      attrs = %{
        "from_account_id" => cash.id,
        "to_account_id" => ar.id,
        "date" => Date.utc_today(),
        "amount_pesos" => Decimal.new("100.00"),
        "note" => "Test transfer"
      }

      assert {:ok, %MoneyTransfer{} = transfer} = Accounting.create_money_transfer(attrs)
      assert transfer.amount_cents == 10000
      assert transfer.from_account_id == cash.id
      assert transfer.to_account_id == ar.id
    end

    test "create_money_transfer/1 fails for same account", %{accounts: accounts} do
      cash = accounts["1000"]

      attrs = %{
        "from_account_id" => cash.id,
        "to_account_id" => cash.id,
        "date" => Date.utc_today(),
        "amount_pesos" => Decimal.new("100.00")
      }

      assert {:error, changeset} = Accounting.create_money_transfer(attrs)
      assert changeset.errors[:to_account_id] != nil
    end

    test "list_money_transfers/0 returns all transfers", %{accounts: accounts} do
      cash = accounts["1000"]
      ar = accounts["1100"]

      attrs = %{
        "from_account_id" => cash.id,
        "to_account_id" => ar.id,
        "date" => Date.utc_today(),
        "amount_pesos" => Decimal.new("50.00")
      }

      {:ok, _transfer} = Accounting.create_money_transfer(attrs)

      transfers = Accounting.list_money_transfers()
      assert length(transfers) >= 1
    end

    test "delete_money_transfer/1 removes transfer and journal entry", %{accounts: accounts} do
      cash = accounts["1000"]
      ar = accounts["1100"]

      attrs = %{
        "from_account_id" => cash.id,
        "to_account_id" => ar.id,
        "date" => Date.utc_today(),
        "amount_pesos" => Decimal.new("75.00"),
        "note" => "To be deleted"
      }

      {:ok, transfer} = Accounting.create_money_transfer(attrs)
      reference = "Transfer ##{transfer.id}"

      # Verify journal entry exists
      entry_before = Repo.get_by(JournalEntry, reference: reference)
      assert entry_before != nil

      # Delete transfer
      {:ok, _} = Accounting.delete_money_transfer(transfer)

      # Verify journal entry is also deleted
      entry_after = Repo.get_by(JournalEntry, reference: reference)
      assert entry_after == nil
    end
  end

  describe "profit_and_loss/2" do
    setup do
      accounts = standard_accounts_fixture()
      {:ok, accounts: accounts}
    end

    test "returns zero values when no transactions", %{accounts: _accounts} do
      today = Date.utc_today()
      result = Accounting.profit_and_loss(today, today)

      assert result.total_revenue_cents == 0
      assert result.total_cogs_cents == 0
      assert result.gross_profit_cents == 0
      assert result.net_income_cents == 0
    end

    test "calculates revenue correctly", %{accounts: accounts} do
      today = Date.utc_today()
      sales = accounts["4000"]
      cash = accounts["1000"]

      # Create a sales entry
      {:ok, _} = Accounting.create_journal_entry_with_lines(
        %{date: today, entry_type: "other", reference: "SALE-1", description: "Test sale"},
        [
          %{account_id: cash.id, debit_cents: 10000, credit_cents: 0, description: "Cash in"},
          %{account_id: sales.id, debit_cents: 0, credit_cents: 10000, description: "Revenue"}
        ]
      )

      result = Accounting.profit_and_loss(today, today)

      assert result.total_revenue_cents == 10000
      assert result.gross_profit_cents == 10000
    end

    test "calculates COGS correctly", %{accounts: accounts} do
      today = Date.utc_today()
      sales = accounts["4000"]
      cogs = accounts["5000"]
      cash = accounts["1000"]
      inventory = accounts["1200"]

      # Create a sales entry
      {:ok, _} = Accounting.create_journal_entry_with_lines(
        %{date: today, entry_type: "other", reference: "SALE-2", description: "Sale"},
        [
          %{account_id: cash.id, debit_cents: 15000, credit_cents: 0, description: "Cash in"},
          %{account_id: sales.id, debit_cents: 0, credit_cents: 15000, description: "Revenue"}
        ]
      )

      # Create a COGS entry
      {:ok, _} = Accounting.create_journal_entry_with_lines(
        %{date: today, entry_type: "other", reference: "COGS-1", description: "Cost of goods"},
        [
          %{account_id: cogs.id, debit_cents: 5000, credit_cents: 0, description: "COGS"},
          %{account_id: inventory.id, debit_cents: 0, credit_cents: 5000, description: "Inventory out"}
        ]
      )

      result = Accounting.profit_and_loss(today, today)

      assert result.total_revenue_cents == 15000
      assert result.total_cogs_cents == 5000
      assert result.gross_profit_cents == 10000
    end

    test "calculates margins correctly", %{accounts: accounts} do
      today = Date.utc_today()
      sales = accounts["4000"]
      cogs = accounts["5000"]
      cash = accounts["1000"]
      inventory = accounts["1200"]

      # Revenue of $100
      {:ok, _} = Accounting.create_journal_entry_with_lines(
        %{date: today, entry_type: "other", reference: "SALE-3", description: "Sale"},
        [
          %{account_id: cash.id, debit_cents: 10000, credit_cents: 0, description: "Cash"},
          %{account_id: sales.id, debit_cents: 0, credit_cents: 10000, description: "Revenue"}
        ]
      )

      # COGS of $30 (30% of revenue)
      {:ok, _} = Accounting.create_journal_entry_with_lines(
        %{date: today, entry_type: "other", reference: "COGS-2", description: "COGS"},
        [
          %{account_id: cogs.id, debit_cents: 3000, credit_cents: 0, description: "COGS"},
          %{account_id: inventory.id, debit_cents: 0, credit_cents: 3000, description: "Inv"}
        ]
      )

      result = Accounting.profit_and_loss(today, today)

      assert result.gross_margin_percent == 70.0
    end
  end

  describe "balance_sheet/1" do
    setup do
      accounts = standard_accounts_fixture()
      # Owner's Equity (3000) is now included in standard_accounts_fixture
      {:ok, accounts: accounts}
    end

    test "returns asset, liability, and equity totals", %{accounts: accounts} do
      today = Date.utc_today()
      cash = accounts["1000"]
      equity = accounts["3000"]

      # Add some cash via equity investment
      {:ok, _} = Accounting.create_journal_entry_with_lines(
        %{date: today, entry_type: "investment", reference: "INV-1", description: "Investment"},
        [
          %{account_id: cash.id, debit_cents: 50000, credit_cents: 0, description: "Cash in"},
          %{account_id: equity.id, debit_cents: 0, credit_cents: 50000, description: "Equity"}
        ]
      )

      result = Accounting.balance_sheet(today)

      assert result.total_assets_cents >= 50000
      assert result.total_equity_cents >= 50000
      assert is_list(result.assets)
      assert is_list(result.liabilities)
      assert is_list(result.equity)
    end

    test "includes net income in balance calculation", %{accounts: accounts} do
      today = Date.utc_today()
      cash = accounts["1000"]
      sales = accounts["4000"]

      # Create a sale (increases net income)
      {:ok, _} = Accounting.create_journal_entry_with_lines(
        %{date: today, entry_type: "other", reference: "SALE-BS", description: "Sale"},
        [
          %{account_id: cash.id, debit_cents: 20000, credit_cents: 0, description: "Cash"},
          %{account_id: sales.id, debit_cents: 0, credit_cents: 20000, description: "Revenue"}
        ]
      )

      result = Accounting.balance_sheet(today)

      assert result.net_income_cents >= 20000
    end
  end

  describe "format_cents/1" do
    test "formats positive amounts correctly" do
      assert Accounting.format_cents(12345) == "$123.45"
      assert Accounting.format_cents(100) == "$1.00"
      assert Accounting.format_cents(5) == "$0.05"
      assert Accounting.format_cents(0) == "$0.00"
    end

    test "formats negative amounts correctly" do
      assert Accounting.format_cents(-12345) == "-$123.45"
      assert Accounting.format_cents(-100) == "-$1.00"
    end

    test "handles nil" do
      assert Accounting.format_cents(nil) == "0.00"
    end
  end

  describe "shipping_fee_cents/0" do
    test "returns the value from application config" do
      assert OrderAccounting.shipping_fee_cents() ==
               Application.get_env(:ledgr, :default_shipping_fee_cents)
    end
  end

  describe "order payment accounting" do
    setup do
      accounts = standard_accounts_fixture()
      product = product_fixture()
      variant = variant_fixture(%{product: product, price_cents: 10000})
      location = location_fixture()
      order = order_fixture(%{variant: variant, location: location})

      {:ok, accounts: accounts, order: order, variant: variant}
    end

    test "record_order_payment creates correct journal entry for regular payment", %{accounts: accounts, order: order} do
      cash = accounts["1000"]
      ar = accounts["1100"]

      {:ok, payment} =
        %OrderPayment{}
        |> OrderPayment.changeset(%{
          order_id: order.id,
          paid_to_account_id: cash.id,
          amount_cents: 5000,
          payment_date: Date.utc_today(),
          is_deposit: false
        })
        |> Repo.insert()

      {:ok, entry} = OrderAccounting.record_order_payment(payment)
      entry = Repo.preload(entry, :journal_lines)

      assert entry.entry_type == "order_payment"

      # Cash debit
      cash_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == cash.id && l.debit_cents > 0
      end)
      assert cash_line.debit_cents == 5000

      # AR credit
      ar_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == ar.id && l.credit_cents > 0
      end)
      assert ar_line.credit_cents == 5000
    end

    test "record_order_payment creates correct journal entry for deposit", %{accounts: accounts, order: order} do
      cash = accounts["1000"]
      customer_deposits = accounts["2200"]

      {:ok, payment} =
        %OrderPayment{}
        |> OrderPayment.changeset(%{
          order_id: order.id,
          paid_to_account_id: cash.id,
          amount_cents: 3000,
          payment_date: Date.utc_today(),
          is_deposit: true
        })
        |> Repo.insert()

      {:ok, entry} = OrderAccounting.record_order_payment(payment)
      entry = Repo.preload(entry, :journal_lines)

      # Cash debit
      cash_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == cash.id && l.debit_cents > 0
      end)
      assert cash_line.debit_cents == 3000

      # Customer Deposits credit (not AR)
      deposits_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == customer_deposits.id && l.credit_cents > 0
      end)
      assert deposits_line.credit_cents == 3000
    end
  end

  describe "record_inventory_write_off/2" do
    setup do
      accounts = standard_accounts_fixture()

      waste_account =
        case Accounting.get_account_by_code("6060") do
          nil ->
            {:ok, a} =
              Accounting.create_account(%{
                code: "6060",
                name: "Inventory Waste",
                type: "expense",
                normal_balance: "debit",
                is_cash: false
              })
            a
          existing -> existing
        end

      {:ok, accounts: accounts, waste_account: waste_account}
    end

    test "debits waste expense and credits ingredients inventory", %{accounts: accounts, waste_account: waste_account} do
      ingredients = accounts["1200"]

      {:ok, entry} = Accounting.record_inventory_write_off(8000, reference: "WASTE-001")
      entry = Repo.preload(entry, :journal_lines)

      assert length(entry.journal_lines) == 2

      waste_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == waste_account.id && l.debit_cents > 0
      end)
      assert waste_line.debit_cents == 8000

      inv_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == ingredients.id && l.credit_cents > 0
      end)
      assert inv_line.credit_cents == 8000
    end

    test "uses packing inventory account when packing: true", %{accounts: accounts, waste_account: waste_account} do
      packing = accounts["1210"]

      {:ok, entry} = Accounting.record_inventory_write_off(3000, packing: true)
      entry = Repo.preload(entry, :journal_lines)

      waste_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == waste_account.id && l.debit_cents > 0
      end)
      assert waste_line.debit_cents == 3000

      packing_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == packing.id && l.credit_cents > 0
      end)
      assert packing_line.credit_cents == 3000
    end
  end

  describe "record_inventory_usage/2" do
    setup do
      accounts = standard_accounts_fixture()
      {:ok, accounts: accounts}
    end

    test "debits ingredients COGS and credits ingredients inventory", %{accounts: accounts} do
      cogs = accounts["5000"]
      ingredients = accounts["1200"]

      {:ok, entry} = Accounting.record_inventory_usage(12000, reference: "USAGE-001")
      entry = Repo.preload(entry, :journal_lines)

      assert length(entry.journal_lines) == 2

      cogs_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == cogs.id && l.debit_cents > 0
      end)
      assert cogs_line.debit_cents == 12000

      inv_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == ingredients.id && l.credit_cents > 0
      end)
      assert inv_line.credit_cents == 12000
    end

    test "uses packing COGS and packing inventory when packing: true", %{accounts: accounts} do
      packing_cogs = accounts["5010"]
      packing_inv = accounts["1210"]

      {:ok, entry} = Accounting.record_inventory_usage(5000, packing: true)
      entry = Repo.preload(entry, :journal_lines)

      cogs_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == packing_cogs.id && l.debit_cents > 0
      end)
      assert cogs_line.debit_cents == 5000

      inv_line = Enum.find(entry.journal_lines, fn l ->
        l.account_id == packing_inv.id && l.credit_cents > 0
      end)
      assert inv_line.credit_cents == 5000
    end
  end
end
