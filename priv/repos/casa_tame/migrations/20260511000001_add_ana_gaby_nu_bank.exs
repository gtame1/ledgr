defmodule Ledgr.Repos.CasaTame.Migrations.AddAnaGabyNuBank do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at)
    VALUES ('1111', 'Ana Gaby Nu Bank (MXN)', 'asset', 'debit', true, false, NOW(), NOW())
    """
  end

  def down do
    execute "DELETE FROM accounts WHERE code = '1111'"
  end
end
