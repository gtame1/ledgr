defmodule Ledgr.Domains.MrMunchMe.Orders.ProductVariant do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.MrMunchMe.Orders.Product

  schema "product_variants" do
    field :name, :string
    field :sku, :string
    field :price_cents, :integer
    field :active, :boolean, default: true

    belongs_to :product, Product
    has_many :orders, Ledgr.Domains.MrMunchMe.Orders.Order, foreign_key: :variant_id
    has_many :recipes, Ledgr.Domains.MrMunchMe.Inventory.Recipe, foreign_key: :variant_id

    timestamps()
  end

  def changeset(variant, attrs) do
    variant
    |> cast(attrs, [:name, :sku, :price_cents, :active, :product_id])
    |> validate_required([:name, :price_cents, :product_id])
    |> validate_number(:price_cents, greater_than: 0)
    |> unique_constraint(:sku)
    |> assoc_constraint(:product)
  end
end
