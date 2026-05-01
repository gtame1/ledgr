defmodule Ledgr.Domains.MrMunchMe.Orders.DiscountCode do
  use Ecto.Schema
  import Ecto.Changeset

  @discount_types ~w(flat percentage)

  schema "discount_codes" do
    field :code, :string
    field :discount_type, :string
    field :discount_value, :decimal
    field :active, :boolean, default: true
    field :max_uses, :integer
    field :uses_count, :integer, default: 0
    field :expires_at, :date

    timestamps()
  end

  def changeset(discount_code, attrs) do
    discount_code
    |> cast(attrs, [
      :code,
      :discount_type,
      :discount_value,
      :active,
      :max_uses,
      :uses_count,
      :expires_at
    ])
    |> validate_required([:code, :discount_type, :discount_value])
    |> validate_inclusion(:discount_type, @discount_types)
    |> validate_number(:discount_value, greater_than: 0)
    |> validate_percentage_cap()
    |> update_change(:code, &String.upcase/1)
    |> unique_constraint(:code)
  end

  defp validate_percentage_cap(changeset) do
    if get_field(changeset, :discount_type) == "percentage" do
      validate_number(changeset, :discount_value, less_than_or_equal_to: 100)
    else
      changeset
    end
  end
end
