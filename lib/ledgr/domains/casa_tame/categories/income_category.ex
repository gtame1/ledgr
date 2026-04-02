defmodule Ledgr.Domains.CasaTame.Categories.IncomeCategory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "income_categories" do
    field :name, :string
    field :icon, :string
    field :is_system, :boolean, default: false

    timestamps()
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :icon, :is_system])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
