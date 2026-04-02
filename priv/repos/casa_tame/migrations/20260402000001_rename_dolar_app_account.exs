defmodule Ledgr.Repos.CasaTame.Migrations.RenameDolarAppAccount do
  use Ecto.Migration

  def up do
    execute "UPDATE accounts SET name = 'ARQ (Dolar App)' WHERE code = '1004'"
  end

  def down do
    execute "UPDATE accounts SET name = 'Dolar App' WHERE code = '1004'"
  end
end
