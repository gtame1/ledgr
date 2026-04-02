defmodule Ledgr.Repos.CasaTame.Migrations.SeedRealAccounts do
  use Ecto.Migration

  @moduledoc """
  Replaces generic placeholder accounts with real Casa Tame accounts.
  Deletes old accounts (no journal lines reference them yet) and inserts the real chart.
  """

  def up do
    # Delete old placeholder accounts that have no journal lines
    execute("DELETE FROM accounts WHERE code IN ('1000','1010','1020','1100','1110','1120','1130')")

    now = "NOW()"

    # ── MXN ASSETS ───────────────────────────────────────────
    # Cash (MXN) 1100-1109
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1100', 'Cartera Guillo (MXN)', 'asset', 'debit', true, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1101', 'Cartera Ana Gaby (MXN)', 'asset', 'debit', true, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1102', 'Caja Casa (MXN)', 'asset', 'debit', true, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1103', 'Otros Efectivo (MXN)', 'asset', 'debit', true, false, #{now}, #{now})"

    # Bank (MXN) 1110-1119
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1110', 'Santander Guillo', 'asset', 'debit', true, false, #{now}, #{now})"

    # Fixed Assets (MXN) 1150-1159
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1150', 'Departamento Avivia 703', 'asset', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1151', 'BYD Dolphin', 'asset', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1152', 'BYD Song Pro', 'asset', 'debit', false, false, #{now}, #{now})"

    # ── USD ASSETS ───────────────────────────────────────────
    # Cash (USD) 1000-1009
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1000', 'Cartera Guillo (USD)', 'asset', 'debit', true, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1001', 'Cartera Ana Gaby (USD)', 'asset', 'debit', true, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1002', 'Caja Casa (USD)', 'asset', 'debit', true, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1003', 'Otros Efectivo (USD)', 'asset', 'debit', true, false, #{now}, #{now})"

    # Bank (USD) 1010-1019
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1010', 'BoA Checking', 'asset', 'debit', true, false, #{now}, #{now})"

    # Investment Accounts (USD) 1050-1059
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1050', 'Schwab', 'asset', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1051', 'Coinbase', 'asset', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('1052', 'Angel Investments', 'asset', 'debit', false, false, #{now}, #{now})"

    # ── MXN LIABILITIES ──────────────────────────────────────
    # Credit Cards (MXN) 2100-2109
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2100', 'TDC Plata', 'liability', 'credit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2101', 'TDC Santander', 'liability', 'credit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2102', 'TDC Nelo', 'liability', 'credit', false, false, #{now}, #{now})"

    # Accounts Payable (MXN) 2110-2119
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2110', 'Deudas Papa Ana Gaby', 'liability', 'credit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2111', 'Deudas Papa Guillo', 'liability', 'credit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2112', 'Deudas Mama Ana Gaby', 'liability', 'credit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2113', 'Deudas Mama Guillo', 'liability', 'credit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2114', 'Deudas Otros (MXN)', 'liability', 'credit', false, false, #{now}, #{now})"

    # Long Term Loans (MXN) 2150-2159
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2150', 'Credito BYD Dolphin', 'liability', 'credit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2151', 'Credito BYD Song Pro', 'liability', 'credit', false, false, #{now}, #{now})"

    # ── USD LIABILITIES ──────────────────────────────────────
    # Credit Cards (USD) 2000-2009
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2000', 'Amex CC', 'liability', 'credit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2001', 'Apple CC', 'liability', 'credit', false, false, #{now}, #{now})"

    # Accounts Payable (USD) 2010-2019
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2010', 'General AP (USD)', 'liability', 'credit', false, false, #{now}, #{now})"

    # Long Term Loans (USD) 2050-2059
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2050', 'Student Loan', 'liability', 'credit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('2051', 'Angel Vazquez Loan', 'liability', 'credit', false, false, #{now}, #{now})"
  end

  def down do
    # Remove all the real accounts
    execute "DELETE FROM accounts WHERE code BETWEEN '1000' AND '1199'"
    execute "DELETE FROM accounts WHERE code BETWEEN '2000' AND '2199'"
  end
end
