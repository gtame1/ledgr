defmodule Ledgr.Repos.CasaTame.Migrations.UpdateAccountsEnglishAndExpenses do
  use Ecto.Migration

  @moduledoc """
  1. Renames all accounts to English
  2. Replaces generic expense accounts with detailed sub-accounts
  """

  def up do
    now = "NOW()"

    # ── Rename asset accounts to English ─────────────────────
    execute "UPDATE accounts SET name = 'Guillo Wallet (MXN)' WHERE code = '1100'"
    execute "UPDATE accounts SET name = 'Ana Gaby Wallet (MXN)' WHERE code = '1101'"
    execute "UPDATE accounts SET name = 'House Cash (MXN)' WHERE code = '1102'"
    execute "UPDATE accounts SET name = 'Other Cash (MXN)' WHERE code = '1103'"
    execute "UPDATE accounts SET name = 'Santander Guillo (MXN)' WHERE code = '1110'"
    execute "UPDATE accounts SET name = 'Apartment Avivia 703' WHERE code = '1150'"

    execute "UPDATE accounts SET name = 'Guillo Wallet (USD)' WHERE code = '1000'"
    execute "UPDATE accounts SET name = 'Ana Gaby Wallet (USD)' WHERE code = '1001'"
    execute "UPDATE accounts SET name = 'House Cash (USD)' WHERE code = '1002'"
    execute "UPDATE accounts SET name = 'Other Cash (USD)' WHERE code = '1003'"
    execute "UPDATE accounts SET name = 'BoA Checking (USD)' WHERE code = '1010'"

    # ── Rename liability accounts to English ─────────────────
    execute "UPDATE accounts SET name = 'AP - Ana Gaby''s Dad' WHERE code = '2110'"
    execute "UPDATE accounts SET name = 'AP - Guillo''s Dad' WHERE code = '2111'"
    execute "UPDATE accounts SET name = 'AP - Ana Gaby''s Mom' WHERE code = '2112'"
    execute "UPDATE accounts SET name = 'AP - Guillo''s Mom' WHERE code = '2113'"
    execute "UPDATE accounts SET name = 'AP - Other (MXN)' WHERE code = '2114'"
    execute "UPDATE accounts SET name = 'Car Loan - BYD Dolphin' WHERE code = '2150'"
    execute "UPDATE accounts SET name = 'Car Loan - BYD Song Pro' WHERE code = '2151'"

    # ── Rename revenue accounts to English ───────────────────
    # (already in English, no changes needed)

    # ── Delete old generic expense accounts ──────────────────
    execute "DELETE FROM accounts WHERE code IN ('6000','6010','6020','6030','6040','6050','6060','6070','6080','6090','6099')"

    # ── Insert detailed expense accounts ─────────────────────

    # Transportation (6000-6009)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6000', 'Auto & Transportation', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6001', 'Gas & Fuel', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6002', 'Parking & Tolls', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6003', 'Car Insurance', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6004', 'Car Maintenance & Repairs', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6005', 'Ride Sharing & Taxis', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6006', 'Car Loan Payments', 'expense', 'debit', false, false, #{now}, #{now})"

    # Household Staff (6010-6014)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6010', 'Housekeeper & Drivers', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6011', 'Housekeeper Salary', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6012', 'Driver / Chauffeur', 'expense', 'debit', false, false, #{now}, #{now})"

    # Utilities (6020-6029)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6020', 'Utilities', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6021', 'Electricity', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6022', 'Water', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6023', 'Gas (Home)', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6024', 'Internet & Phone', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6025', 'HOA / Condo Fees', 'expense', 'debit', false, false, #{now}, #{now})"

    # Home Maintenance (6030-6034)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6030', 'Apartment Maintenance (Avivia)', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6031', 'Home Repairs & Fixes', 'expense', 'debit', false, false, #{now}, #{now})"

    # Furniture & Decor (6035-6039)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6035', 'Furniture & Decor', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6036', 'Appliances', 'expense', 'debit', false, false, #{now}, #{now})"

    # Education (6040-6044)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6040', 'Education', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6041', 'Courses & Training', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6042', 'Books & Materials', 'expense', 'debit', false, false, #{now}, #{now})"

    # Entertainment (6050-6054)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6050', 'Entertainment', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6051', 'Streaming & Subscriptions', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6052', 'Going Out & Events', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6053', 'Hobbies & Sports', 'expense', 'debit', false, false, #{now}, #{now})"

    # Food & Dining (6060-6069)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6060', 'Coffee Shops & Cafes', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6061', 'Groceries & Supermarket', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6062', 'Fast Food & Snacks', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6063', 'Restaurants & Bars', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6064', 'Food Delivery', 'expense', 'debit', false, false, #{now}, #{now})"

    # Health (6070-6079)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6070', 'Health Insurance', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6071', 'Health & Personal Care', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6072', 'Doctor & Specialist', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6073', 'Pharmacy', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6074', 'Dental & Vision', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6075', 'Gym & Fitness', 'expense', 'debit', false, false, #{now}, #{now})"

    # Kids (6080-6084)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6080', 'Kids', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6081', 'Kids - Daycare & School', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6082', 'Kids - Supplies & Clothing', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6083', 'Kids - Activities & Toys', 'expense', 'debit', false, false, #{now}, #{now})"

    # Shopping (6085-6089)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6085', 'Shopping', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6086', 'Clothing & Accessories', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6087', 'Electronics & Gadgets', 'expense', 'debit', false, false, #{now}, #{now})"

    # Travel (6090-6094)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6090', 'Travel', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6091', 'Flights', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6092', 'Hotels & Lodging', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6093', 'Travel Activities & Tours', 'expense', 'debit', false, false, #{now}, #{now})"

    # Pets (6095-6097)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6095', 'Pets', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6096', 'Pet Food & Supplies', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6097', 'Vet & Pet Health', 'expense', 'debit', false, false, #{now}, #{now})"

    # Financial & Other (6098-6099)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6098', 'Bank & Financial Fees', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6099', 'Other Expenses', 'expense', 'debit', false, false, #{now}, #{now})"

    # Gifts & Donations (6100-6101)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6100', 'Gifts Given', 'expense', 'debit', false, false, #{now}, #{now})"
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6101', 'Donations & Charity', 'expense', 'debit', false, false, #{now}, #{now})"

    # Taxes (6105)
    execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('6105', 'Taxes', 'expense', 'debit', false, false, #{now}, #{now})"
  end

  def down do
    # Delete all new expense accounts
    execute "DELETE FROM accounts WHERE code >= '6000' AND code <= '6199'"

    # Re-insert old generic ones
    now = "NOW()"
    for {code, name} <- [
      {"6000", "Housing"}, {"6010", "Food & Dining"}, {"6020", "Transportation"},
      {"6030", "Healthcare"}, {"6040", "Entertainment"}, {"6050", "Personal"},
      {"6060", "Financial Fees"}, {"6070", "Pets"}, {"6080", "Travel"},
      {"6090", "Subscriptions"}, {"6099", "Other Expenses"}
    ] do
      execute "INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at) VALUES ('#{code}', '#{name}', 'expense', 'debit', false, false, #{now}, #{now})"
    end
  end
end
