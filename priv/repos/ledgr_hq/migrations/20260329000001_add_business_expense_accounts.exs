defmodule Ledgr.Repos.LedgrHQ.Migrations.AddBusinessExpenseAccounts do
  use Ecto.Migration

  def up do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    accounts = [
      %{code: "5300", name: "Contractor Payments",  type: "expense", normal_balance: "debit", is_cash: false, is_cogs: false},
      %{code: "5400", name: "Legal & Compliance",   type: "expense", normal_balance: "debit", is_cash: false, is_cogs: false},
      %{code: "5500", name: "Marketing & Growth",   type: "expense", normal_balance: "debit", is_cash: false, is_cogs: false},
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
    execute "DELETE FROM accounts WHERE code IN ('5300','5400','5500')"
  end
end
