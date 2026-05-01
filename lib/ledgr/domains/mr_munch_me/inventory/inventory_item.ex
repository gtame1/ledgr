defmodule Ledgr.Domains.MrMunchMe.Inventory.InventoryItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.MrMunchMe.Inventory.{Ingredient, Location}

  schema "inventories" do
    field :quantity_on_hand, :integer, default: 0
    field :avg_cost_per_unit_cents, :integer, default: 0
    field :negative_stock, :boolean, default: false

    belongs_to :ingredient, Ingredient
    belongs_to :location, Location

    timestamps()
  end

  def changeset(stock, attrs) do
    stock
    |> cast(attrs, [
      :quantity_on_hand,
      :avg_cost_per_unit_cents,
      :ingredient_id,
      :location_id,
      :negative_stock
    ])
    |> validate_required([
      :quantity_on_hand,
      :avg_cost_per_unit_cents,
      :ingredient_id,
      :location_id
    ])
  end
end
