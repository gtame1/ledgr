defmodule Ledgr.Repos.LedgrHQ.Migrations.SeedAccounts do
  use Ecto.Migration

  def up do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    accounts = [
      # Assets
      %{code: "1000", name: "Cash",                    type: "asset",   normal_balance: "debit",  is_cash: true,  is_cogs: false},
      %{code: "1010", name: "Bank Transfer",           type: "asset",   normal_balance: "debit",  is_cash: true,  is_cogs: false},
      %{code: "1100", name: "Accounts Receivable",     type: "asset",   normal_balance: "debit",  is_cash: false, is_cogs: false},
      # Equity
      %{code: "3000", name: "Owners Equity",           type: "equity",  normal_balance: "credit", is_cash: false, is_cogs: false},
      %{code: "3050", name: "Retained Earnings",       type: "equity",  normal_balance: "credit", is_cash: false, is_cogs: false},
      %{code: "3100", name: "Owners Drawings",         type: "equity",  normal_balance: "debit",  is_cash: false, is_cogs: false},
      # Revenue
      %{code: "4000", name: "Subscription Revenue",   type: "revenue", normal_balance: "credit", is_cash: false, is_cogs: false},
      # Expenses
      %{code: "5100", name: "Hosting Expense",         type: "expense", normal_balance: "debit",  is_cash: false, is_cogs: false},
      %{code: "5110", name: "Domain & DNS Expense",    type: "expense", normal_balance: "debit",  is_cash: false, is_cogs: false},
      %{code: "5120", name: "SaaS Tools Expense",      type: "expense", normal_balance: "debit",  is_cash: false, is_cogs: false},
      %{code: "5200", name: "General Expense",         type: "expense", normal_balance: "debit",  is_cash: false, is_cogs: false},
    ]

    Enum.each(accounts, fn acc ->
      execute """
        INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at)
        VALUES ('#{acc.code}', '#{acc.name}', '#{acc.type}', '#{acc.normal_balance}',
                #{acc.is_cash}, #{acc.is_cogs}, '#{now}', '#{now}')
        ON CONFLICT (code) DO NOTHING
      """
    end)
  end

  def down do
    execute "DELETE FROM accounts WHERE code IN ('1000','1010','1100','3000','3050','3100','4000','5100','5110','5120','5200')"
  end
end
