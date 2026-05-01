defmodule Ledgr.Repo.Migrations.CreateProductsAndOrders do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :name, :string, null: false
      add :sku, :string
      add :price_cents, :integer, null: false
      add :active, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:products, [:sku])

    create table(:orders) do
      add :customer_name, :string, null: false
      add :customer_email, :string
      add :customer_phone, :string, null: false

      # "pickup" | "delivery"
      add :delivery_type, :string, null: false
      add :delivery_address, :text
      add :delivery_date, :date, null: false
      # optional
      add :delivery_time, :time

      add :status, :string, null: false, default: "new_order"
      add :product_id, references(:products, on_delete: :restrict), null: false

      timestamps()
    end

    create index(:orders, [:product_id])
    create index(:orders, [:status])
  end
end
