defmodule Ledgr.Repos.MrMunchMe.Migrations.AddOwedChangeApAccount do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at)
    VALUES ('2300', 'Owed Change Payable', 'liability', 'credit', false, false, NOW(), NOW())
    ON CONFLICT (code) DO NOTHING
    """
  end

  def down do
    execute "DELETE FROM accounts WHERE code = '2300'"
  end
end
