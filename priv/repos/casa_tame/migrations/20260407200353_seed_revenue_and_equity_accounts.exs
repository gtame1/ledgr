defmodule Ledgr.Repos.CasaTame.Migrations.SeedRevenueAndEquityAccounts do
  use Ecto.Migration

  @moduledoc """
  Seeds revenue (4xxx) and equity (3xxx) accounts that were missing from
  the original seed migration. These are required for income journal entries
  and balance sheet calculations.
  """

  def up do
    now = "NOW()"

    # ── EQUITY ────────────────────────────────────────────────
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('3000', 'Owner''s Equity', 'equity', 'credit', false, false, #{now}, #{now}) ON CONFLICT (code) DO NOTHING"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('3050', 'Retained Earnings', 'equity', 'credit', false, false, #{now}, #{now}) ON CONFLICT (code) DO NOTHING"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('3100', 'Owner''s Drawings', 'equity', 'debit', false, false, #{now}, #{now}) ON CONFLICT (code) DO NOTHING"

    # ── REVENUE (USD) ─────────────────────────────────────────
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('4000', 'Wages & Salary (USD)', 'revenue', 'credit', false, false, #{now}, #{now}) ON CONFLICT (code) DO NOTHING"

    # ── REVENUE (MXN) ─────────────────────────────────────────
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('4010', 'Wages & Salary (MXN)', 'revenue', 'credit', false, false, #{now}, #{now}) ON CONFLICT (code) DO NOTHING"

    # ── REVENUE (shared) ──────────────────────────────────────
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('4020', 'Freelance & Consulting', 'revenue', 'credit', false, false, #{now}, #{now}) ON CONFLICT (code) DO NOTHING"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('4030', 'Investment Returns', 'revenue', 'credit', false, false, #{now}, #{now}) ON CONFLICT (code) DO NOTHING"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('4040', 'Rental Income', 'revenue', 'credit', false, false, #{now}, #{now}) ON CONFLICT (code) DO NOTHING"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('4050', 'Other Income', 'revenue', 'credit', false, false, #{now}, #{now}) ON CONFLICT (code) DO NOTHING"
  end

  def down do
    execute "DELETE FROM accounts WHERE code IN ('3000', '3050', '3100', '4000', '4010', '4020', '4030', '4040', '4050')"
  end
end
