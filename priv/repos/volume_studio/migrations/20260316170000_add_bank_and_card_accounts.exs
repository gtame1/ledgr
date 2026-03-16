defmodule Ledgr.Repos.VolumeStudio.Migrations.AddBankAndCardAccounts do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at)
    VALUES
      ('1010', 'Bank Transfer', 'asset', 'debit', true, false, NOW(), NOW()),
      ('1020', 'Card Terminal', 'asset', 'debit', true, false, NOW(), NOW())
    ON CONFLICT (code) DO NOTHING
    """
  end

  def down do
    execute "DELETE FROM accounts WHERE code IN ('1010', '1020')"
  end
end
