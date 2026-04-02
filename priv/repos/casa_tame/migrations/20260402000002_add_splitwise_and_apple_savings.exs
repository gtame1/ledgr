defmodule Ledgr.Repos.CasaTame.Migrations.AddSplitwiseAndAppleSavings do
  use Ecto.Migration

  def up do
    # USD Asset: Apple Savings (Bank USD 1010-1019)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1011', 'Apple Savings', 'asset', 'debit', true, false, NOW(), NOW())"

    # USD AP: Splitwise Balance (USD) (AP USD 2010-2019)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2011', 'Splitwise Balance (USD)', 'liability', 'credit', false, false, NOW(), NOW())"

    # MXN AP: Splitwise Balance (MXN) (AP MXN 2110-2119)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2115', 'Splitwise Balance (MXN)', 'liability', 'credit', false, false, NOW(), NOW())"
  end

  def down do
    execute "DELETE FROM accounts WHERE code IN ('1011', '2011', '2115')"
  end
end
