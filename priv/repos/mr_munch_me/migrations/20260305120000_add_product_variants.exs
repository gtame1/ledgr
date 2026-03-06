defmodule Ledgr.Repos.MrMunchMe.Migrations.AddProductVariants do
  use Ecto.Migration

  def change do
    # ── 1. Create product_variants table ────────────────────────────────
    create table(:product_variants) do
      add :product_id, references(:products, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :sku, :string
      add :price_cents, :integer, null: false
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:product_variants, [:sku])
    create index(:product_variants, [:product_id])

    # ── 2. Add nullable variant_id to orders ────────────────────────────
    alter table(:orders) do
      add :variant_id, references(:product_variants, on_delete: :restrict)
    end

    create index(:orders, [:variant_id])

    # ── 3. Add nullable variant_id to recipes ───────────────────────────
    alter table(:recipes) do
      add :variant_id, references(:product_variants, on_delete: :restrict)
    end

    create index(:recipes, [:variant_id])
  end
end
