defmodule Ledgr.Repos.CasaTame.Migrations.SeedIncomeCategories do
  use Ecto.Migration

  def up do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    categories = [
      %{name: "Wages & Salary", icon: "💼", is_system: true},
      %{name: "Freelance & Consulting", icon: "💻", is_system: true},
      %{name: "Investment Returns", icon: "📈", is_system: true},
      %{name: "Rental Income", icon: "🏠", is_system: true},
      %{name: "Side Income", icon: "🛠️", is_system: true},
      %{name: "Gifts & Misc", icon: "🎁", is_system: true},
      %{name: "Refunds & Reimbursements", icon: "↩️", is_system: true}
    ]

    for cat <- categories do
      execute """
      INSERT INTO income_categories (name, icon, is_system, inserted_at, updated_at)
      VALUES ('#{cat.name}', '#{cat.icon}', #{cat.is_system}, '#{now}', '#{now}')
      ON CONFLICT (name) DO NOTHING
      """
    end
  end

  def down do
    execute """
    DELETE FROM income_categories
    WHERE is_system = true AND name IN (
      'Wages & Salary', 'Freelance & Consulting', 'Investment Returns',
      'Rental Income', 'Side Income', 'Gifts & Misc', 'Refunds & Reimbursements'
    )
    """
  end
end
