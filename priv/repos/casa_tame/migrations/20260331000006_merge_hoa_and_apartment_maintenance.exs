defmodule Ledgr.Repos.CasaTame.Migrations.MergeHoaAndApartmentMaintenance do
  use Ecto.Migration

  def up do
    # Merge: rename HOA to cover both, delete the separate apartment maintenance
    execute "UPDATE accounts SET name = 'HOA & Building Maintenance' WHERE code = '6025'"
    execute "DELETE FROM accounts WHERE code = '6030'"
  end

  def down do
    execute "UPDATE accounts SET name = 'HOA / Condo Fees' WHERE code = '6025'"
    now = "NOW()"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6030', 'Apartment Maintenance (Avivia)', 'expense', 'debit', false, false, #{now}, #{now})"
  end
end
