defmodule Ledgr.Domains.MrMunchMe.Orders.Product do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.MrMunchMe.Orders.ProductImage
  alias Ledgr.Domains.MrMunchMe.Orders.ProductVariant

  schema "products" do
    field :name, :string
    field :sku, :string
    field :price_cents, :integer
    field :active, :boolean, default: true
    field :description, :string
    field :image_url, :string

    has_many :orders, Ledgr.Domains.MrMunchMe.Orders.Order
    has_many :images, ProductImage, preload_order: [asc: :position]
    has_many :variants, ProductVariant, preload_order: [asc: :inserted_at]

    timestamps()
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :sku, :price_cents, :active, :description, :image_url])
    |> validate_required([:name, :price_cents])
    |> validate_number(:price_cents, greater_than: 0)
  end
end
