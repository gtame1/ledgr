defmodule Ledgr.Repos.Viaxe.Migrations.SuppliersLocationAndRecommendations do
  use Ecto.Migration

  def change do
    # ── Alter Suppliers: add location fields ─────────────────
    alter table(:suppliers) do
      add :country, :string
      add :city, :string
      add :website, :string
      add :address, :text
    end

    # ── Recommendations (curated reference per city) ─────────
    create table(:recommendations) do
      add :city, :string, null: false
      add :country, :string, null: false
      add :category, :string, null: false   # restaurant, hotel, bar, tour, experience, shopping, spa, beach, museum, other
      add :name, :string, null: false
      add :description, :text
      add :address, :string
      add :website, :string
      add :price_range, :string             # $, $$, $$$, $$$$
      add :rating, :integer                 # 1–5
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:recommendations, [:country, :city])
    create index(:recommendations, [:category])

    create constraint(:recommendations, :valid_rating,
      check: "rating IS NULL OR (rating >= 1 AND rating <= 5)"
    )
  end
end
