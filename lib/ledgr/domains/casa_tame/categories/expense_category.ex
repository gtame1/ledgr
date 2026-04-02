defmodule Ledgr.Domains.CasaTame.Categories.ExpenseCategory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "expense_categories" do
    field :name, :string
    field :icon, :string
    field :is_system, :boolean, default: false

    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps()
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :icon, :parent_id, :is_system])
    |> validate_required([:name])
    |> assoc_constraint(:parent)
    |> unique_constraint([:name, :parent_id], name: :expense_categories_name_parent_unique)
  end
end
