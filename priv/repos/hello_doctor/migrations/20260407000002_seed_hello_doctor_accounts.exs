defmodule Ledgr.Repos.HelloDoctor.Migrations.SeedHelloDoctorAccounts do
  use Ecto.Migration

  @doc """
  Seeds the HelloDoctor chart of accounts via migration so they're
  always present after deploy — no manual `bin/ledgr seed` needed.
  """
  def up do
    now = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

    accounts = [
      # Assets
      %{code: "1000", name: "Cash", type: "asset", normal_balance: "debit", is_cash: true, is_cogs: false},
      %{code: "1010", name: "Bank - MXN", type: "asset", normal_balance: "debit", is_cash: true, is_cogs: false},
      %{code: "1020", name: "Bank - USD", type: "asset", normal_balance: "debit", is_cash: true, is_cogs: false},
      %{code: "1100", name: "Accounts Receivable", type: "asset", normal_balance: "debit", is_cash: false, is_cogs: false},
      %{code: "1200", name: "Stripe Receivable", type: "asset", normal_balance: "debit", is_cash: false, is_cogs: false},
      # Liabilities
      %{code: "2000", name: "Doctor Payable", type: "liability", normal_balance: "credit", is_cash: false, is_cogs: false},
      %{code: "2100", name: "Refunds Payable", type: "liability", normal_balance: "credit", is_cash: false, is_cogs: false},
      %{code: "2200", name: "Taxes Payable", type: "liability", normal_balance: "credit", is_cash: false, is_cogs: false},
      # Equity
      %{code: "3000", name: "Owner's Equity", type: "equity", normal_balance: "credit", is_cash: false, is_cogs: false},
      %{code: "3050", name: "Retained Earnings", type: "equity", normal_balance: "credit", is_cash: false, is_cogs: false},
      %{code: "3100", name: "Owner's Drawings", type: "equity", normal_balance: "debit", is_cash: false, is_cogs: false},
      # Revenue
      %{code: "4000", name: "Consultation Revenue", type: "revenue", normal_balance: "credit", is_cash: false, is_cogs: false},
      %{code: "4100", name: "Commission Revenue (15%)", type: "revenue", normal_balance: "credit", is_cash: false, is_cogs: false},
      %{code: "4200", name: "Other Revenue", type: "revenue", normal_balance: "credit", is_cash: false, is_cogs: false},
      # Expenses
      %{code: "6000", name: "Payment Processing Fees", type: "expense", normal_balance: "debit", is_cash: false, is_cogs: false},
      %{code: "6010", name: "Refunds Expense", type: "expense", normal_balance: "debit", is_cash: false, is_cogs: false},
      %{code: "6020", name: "Operating Expense", type: "expense", normal_balance: "debit", is_cash: false, is_cogs: false},
      %{code: "6030", name: "WhatsApp / Messaging Costs", type: "expense", normal_balance: "debit", is_cash: false, is_cogs: false},
      %{code: "6040", name: "Technology & Infrastructure", type: "expense", normal_balance: "debit", is_cash: false, is_cogs: false},
      %{code: "6050", name: "Marketing & Advertising", type: "expense", normal_balance: "debit", is_cash: false, is_cogs: false},
      %{code: "6060", name: "Salaries & Payroll", type: "expense", normal_balance: "debit", is_cash: false, is_cogs: false},
      %{code: "6099", name: "Other Expenses", type: "expense", normal_balance: "debit", is_cash: false, is_cogs: false},
    ]

    for acct <- accounts do
      escaped_name = String.replace(acct.name, "'", "''")

      execute("""
        INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at)
        VALUES ('#{acct.code}', '#{escaped_name}', '#{acct.type}', '#{acct.normal_balance}', #{acct.is_cash}, #{acct.is_cogs}, '#{now}', '#{now}')
        ON CONFLICT (code) DO NOTHING
      """)
    end
  end

  def down do
    # Don't delete accounts on rollback — they may have journal entries
    :ok
  end
end
