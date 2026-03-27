defmodule Ledgr.Repos.MrMunchMe.Migrations.CreateDiscountCodes do
  use Ecto.Migration

  def change do
    create table(:discount_codes) do
      add :code, :string, null: false
      add :discount_type, :string, null: false
      add :discount_value, :decimal, null: false
      add :active, :boolean, default: true, null: false
      add :max_uses, :integer
      add :uses_count, :integer, default: 0, null: false
      add :expires_at, :date

      timestamps()
    end

    create unique_index(:discount_codes, [:code])
  end
end
