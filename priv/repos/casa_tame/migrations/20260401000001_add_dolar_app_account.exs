defmodule Ledgr.Repos.CasaTame.Migrations.AddDolarAppAccount do
  use Ecto.Migration

  def up do
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1004', 'Dolar App', 'asset', 'debit', true, false, NOW(), NOW())"
  end

  def down do
    execute "DELETE FROM accounts WHERE code = '1004'"
  end
end
