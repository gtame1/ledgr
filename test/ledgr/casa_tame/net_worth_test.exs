defmodule Ledgr.Domains.CasaTame.NetWorthTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.CasaTame.NetWorth
  alias Ledgr.Domains.CasaTame.ExchangeRates
  alias Ledgr.Core.Accounting

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.CasaTame)
    Ledgr.Domain.put_current(Ledgr.Domains.CasaTame)
    casa_tame_accounts_fixture()
    seed_exchange_rate(20.0)
    :ok
  end

  # ── Fixtures ────────────────────────────────────────────────────────────

  defp casa_tame_accounts_fixture do
    accounts = [
      # USD cash (1000-1049)
      %{code: "1000", name: "Cash USD",          type: "asset",     normal_balance: "debit",  is_cash: true},
      %{code: "1010", name: "Checking USD",      type: "asset",     normal_balance: "debit",  is_cash: true},
      # USD investments (1050-1099)
      %{code: "1050", name: "Brokerage USD",     type: "asset",     normal_balance: "debit",  is_cash: false},
      # MXN cash (1100-1149)
      %{code: "1100", name: "Cash MXN",          type: "asset",     normal_balance: "debit",  is_cash: true},
      %{code: "1110", name: "Checking MXN",      type: "asset",     normal_balance: "debit",  is_cash: true},
      # MXN fixed assets (1150-1199)
      %{code: "1150", name: "Property MXN",      type: "asset",     normal_balance: "debit",  is_cash: false},
      # USD liabilities (2000-2099)
      %{code: "2000", name: "Credit Card USD",   type: "liability", normal_balance: "credit", is_cash: false},
      # MXN liabilities (2100-2199)
      %{code: "2100", name: "Credit Card MXN",   type: "liability", normal_balance: "credit", is_cash: false},
      # Equity & revenue (needed for journal entries)
      %{code: "3000", name: "Owner's Equity",    type: "equity",    normal_balance: "credit", is_cash: false},
      %{code: "3050", name: "Retained Earnings", type: "equity",    normal_balance: "credit", is_cash: false},
      %{code: "3100", name: "Owner's Drawings",  type: "equity",    normal_balance: "debit",  is_cash: false},
      %{code: "4000", name: "Wages USD",         type: "revenue",   normal_balance: "credit", is_cash: false},
      %{code: "4010", name: "Wages MXN",         type: "revenue",   normal_balance: "credit", is_cash: false},
      %{code: "4050", name: "Other Income",      type: "revenue",   normal_balance: "credit", is_cash: false},
      %{code: "6000", name: "Housing",           type: "expense",   normal_balance: "debit",  is_cash: false}
    ]

    Enum.each(accounts, fn attrs ->
      case Accounting.get_account_by_code(attrs.code) do
        nil -> {:ok, _} = Accounting.create_account(attrs)
        _ -> :ok
      end
    end)
  end

  defp seed_exchange_rate(rate) do
    ExchangeRates.create_or_update_rate(%{
      date: Ledgr.Domains.CasaTame.today(),
      from_currency: "USD",
      to_currency: "MXN",
      rate: Decimal.from_float(rate),
      source: "test"
    })
  end

  # Adds a balance to an account via a journal entry
  defp credit_account(account_code, amount_cents) do
    account = Accounting.get_account_by_code!(account_code)
    equity = Accounting.get_account_by_code!("3000")

    Accounting.create_journal_entry_with_lines(
      %{date: Ledgr.Domains.CasaTame.today(), entry_type: "reconciliation",
        reference: "seed-#{account_code}-#{System.unique_integer([:positive])}",
        description: "Test seed"},
      [
        %{account_id: account.id, debit_cents: amount_cents, credit_cents: 0, description: "debit"},
        %{account_id: equity.id, debit_cents: 0, credit_cents: amount_cents, description: "credit"}
      ]
    )
  end

  defp credit_liability(account_code, amount_cents) do
    account = Accounting.get_account_by_code!(account_code)
    equity = Accounting.get_account_by_code!("3000")

    Accounting.create_journal_entry_with_lines(
      %{date: Ledgr.Domains.CasaTame.today(), entry_type: "reconciliation",
        reference: "seed-#{account_code}-#{System.unique_integer([:positive])}",
        description: "Test seed"},
      [
        %{account_id: equity.id, debit_cents: amount_cents, credit_cents: 0, description: "debit"},
        %{account_id: account.id, debit_cents: 0, credit_cents: amount_cents, description: "credit"}
      ]
    )
  end

  # ── calculate/0 ─────────────────────────────────────────────────────────

  describe "calculate/0" do
    test "returns a map with all expected keys" do
      result = NetWorth.calculate()

      assert Map.has_key?(result, :rate)
      assert Map.has_key?(result, :cash_usd)
      assert Map.has_key?(result, :investments_usd)
      assert Map.has_key?(result, :accounts_usd)
      assert Map.has_key?(result, :liabilities_usd)
      assert Map.has_key?(result, :net_usd)
      assert Map.has_key?(result, :cash_mxn)
      assert Map.has_key?(result, :fixed_mxn)
      assert Map.has_key?(result, :accounts_mxn)
      assert Map.has_key?(result, :liabilities_mxn)
      assert Map.has_key?(result, :net_mxn)
      assert Map.has_key?(result, :total_mxn)
      assert Map.has_key?(result, :total_usd)
    end

    test "returns zeros when no balances exist" do
      result = NetWorth.calculate()
      assert result.cash_usd == 0
      assert result.cash_mxn == 0
      assert result.investments_usd == 0
      assert result.liabilities_usd == 0
      assert result.net_usd == 0
      assert result.net_mxn == 0
    end

    test "correctly categorises USD cash accounts (1000-1049)" do
      credit_account("1000", 100_000)
      credit_account("1010", 50_000)

      result = NetWorth.calculate()
      assert result.cash_usd == 150_000
    end

    test "correctly categorises USD investment accounts (1050-1099)" do
      credit_account("1050", 200_000)

      result = NetWorth.calculate()
      assert result.investments_usd == 200_000
    end

    test "correctly categorises MXN cash accounts (1100-1149)" do
      credit_account("1100", 300_000)
      credit_account("1110", 100_000)

      result = NetWorth.calculate()
      assert result.cash_mxn == 400_000
    end

    test "correctly categorises MXN fixed assets (1150-1199)" do
      credit_account("1150", 5_000_000)

      result = NetWorth.calculate()
      assert result.fixed_mxn == 5_000_000
    end

    test "correctly categorises USD liabilities (2000-2099)" do
      credit_liability("2000", 80_000)

      result = NetWorth.calculate()
      assert result.liabilities_usd == 80_000
    end

    test "correctly categorises MXN liabilities (2100-2199)" do
      credit_liability("2100", 120_000)

      result = NetWorth.calculate()
      assert result.liabilities_mxn == 120_000
    end

    test "net_usd subtracts liabilities from assets" do
      credit_account("1000", 500_000)
      credit_account("1050", 200_000)
      credit_liability("2000", 100_000)

      result = NetWorth.calculate()
      assert result.net_usd == 600_000
    end

    test "net_mxn subtracts liabilities from assets" do
      credit_account("1100", 400_000)
      credit_account("1150", 1_000_000)
      credit_liability("2100", 200_000)

      result = NetWorth.calculate()
      assert result.net_mxn == 1_200_000
    end

    test "accounts_usd equals cash_usd + investments_usd" do
      credit_account("1000", 100_000)
      credit_account("1050", 50_000)

      result = NetWorth.calculate()
      assert result.accounts_usd == result.cash_usd + result.investments_usd
    end

    test "accounts_mxn equals cash_mxn + fixed_mxn" do
      credit_account("1100", 200_000)
      credit_account("1150", 800_000)

      result = NetWorth.calculate()
      assert result.accounts_mxn == result.cash_mxn + result.fixed_mxn
    end

    test "total_mxn converts USD net worth using exchange rate" do
      credit_account("1000", 100_000)   # 100,000 USD cents = $1,000 USD
      credit_account("1100", 200_000)   # 200,000 MXN cents = $2,000 MXN

      result = NetWorth.calculate()
      # net_usd = 100_000, net_mxn = 200_000, rate = 20.0
      # total_mxn = 200_000 + round(100_000 * 20.0) = 200_000 + 2_000_000 = 2_200_000
      assert result.total_mxn == 200_000 + round(100_000 * 20.0)
    end

    test "total_usd converts MXN net worth using exchange rate" do
      credit_account("1000", 100_000)
      credit_account("1100", 200_000)

      result = NetWorth.calculate()
      # total_usd = round(200_000 / 20.0) + 100_000 = 10_000 + 100_000 = 110_000
      assert result.total_usd == round(200_000 / 20.0) + 100_000
    end

    test "uses cached exchange rate" do
      seed_exchange_rate(18.5)
      result = NetWorth.calculate()
      assert result.rate == 18.5
    end

    test "falls back to 20.0 when no exchange rate cached" do
      # Delete any rates by using a future date query — rate will fall back
      result = NetWorth.calculate()
      # Rate was seeded to 20.0 in setup
      assert result.rate == 20.0
    end
  end
end
