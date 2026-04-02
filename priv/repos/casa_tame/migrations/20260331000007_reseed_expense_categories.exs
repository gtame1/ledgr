defmodule Ledgr.Repos.CasaTame.Migrations.ReseedExpenseCategories do
  use Ecto.Migration

  @moduledoc """
  Replaces old generic expense categories with ones matching the new
  detailed expense account structure (6000-6105).
  """

  def up do
    # Clear old categories (no expenses reference them yet)
    execute "DELETE FROM expense_categories"

    now = "NOW()"

    # Helper: insert parent, return id
    # We use raw SQL with RETURNING to get IDs for children

    # 1. Auto & Transportation (6000-6006)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Auto & Transportation', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES
      ('Gas & Fuel'), ('Parking & Tolls'), ('Car Insurance'),
      ('Car Maintenance & Repairs'), ('Ride Sharing & Taxis'), ('Car Loan Payments')
    ) AS children(name)
    """

    # 2. Housekeeper & Drivers (6010-6012)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Housekeeper & Drivers', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES ('Housekeeper Salary'), ('Driver / Chauffeur')) AS children(name)
    """

    # 3. Utilities (6020-6025)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Utilities', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES
      ('Electricity'), ('Water'), ('Gas (Home)'),
      ('Internet & Phone'), ('HOA & Building Maintenance')
    ) AS children(name)
    """

    # 4. Home Repairs & Furniture (6031, 6035-6036)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Home & Furniture', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES ('Home Repairs & Fixes'), ('Furniture & Decor'), ('Appliances')) AS children(name)
    """

    # 5. Education (6040-6042)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Education', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES ('Courses & Training'), ('Books & Materials')) AS children(name)
    """

    # 6. Entertainment (6050-6053)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Entertainment', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES
      ('Streaming & Subscriptions'), ('Going Out & Events'), ('Hobbies & Sports')
    ) AS children(name)
    """

    # 7. Food & Dining (6060-6064)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Food & Dining', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES
      ('Coffee Shops & Cafes'), ('Groceries & Supermarket'),
      ('Fast Food & Snacks'), ('Restaurants & Bars'), ('Food Delivery')
    ) AS children(name)
    """

    # 8. Health (6070-6075)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Health & Personal Care', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES
      ('Health Insurance'), ('Personal Care & Grooming'),
      ('Doctor & Specialist'), ('Pharmacy'), ('Dental & Vision'), ('Gym & Fitness')
    ) AS children(name)
    """

    # 9. Kids (6080-6083)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Kids', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES
      ('Daycare & School'), ('Kids Supplies & Clothing'), ('Activities & Toys')
    ) AS children(name)
    """

    # 10. Shopping (6085-6087)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Shopping', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES ('Clothing & Accessories'), ('Electronics & Gadgets')) AS children(name)
    """

    # 11. Travel (6090-6093)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Travel', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES ('Flights'), ('Hotels & Lodging'), ('Travel Activities & Tours')) AS children(name)
    """

    # 12. Pets (6095-6097)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Pets', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES ('Pet Food & Supplies'), ('Vet & Pet Health')) AS children(name)
    """

    # 13. Financial & Other (6098-6105)
    execute """
    WITH parent AS (
      INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
      VALUES ('Financial & Other', NULL, true, #{now}, #{now})
      RETURNING id
    )
    INSERT INTO expense_categories (name, parent_id, is_system, inserted_at, updated_at)
    SELECT name, parent.id, true, #{now}, #{now}
    FROM parent, (VALUES
      ('Bank & Financial Fees'), ('Gifts Given'),
      ('Donations & Charity'), ('Taxes'), ('Other')
    ) AS children(name)
    """
  end

  def down do
    execute "DELETE FROM expense_categories"
  end
end
