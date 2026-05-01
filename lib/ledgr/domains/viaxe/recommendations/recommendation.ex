defmodule Ledgr.Domains.Viaxe.Recommendations.Recommendation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "recommendations" do
    field :city, :string
    field :country, :string
    # restaurant, hotel, bar, tour, experience, shopping, spa, beach, museum, other
    field :category, :string
    field :name, :string
    field :description, :string
    field :address, :string
    field :website, :string
    # $, $$, $$$, $$$$
    field :price_range, :string
    # 1–5
    field :rating, :integer
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:city, :country, :category, :name]
  @optional_fields [:description, :address, :website, :price_range, :rating, :notes]

  @valid_categories ~w(restaurant hotel bar tour experience shopping spa beach museum other)

  def changeset(recommendation, attrs) do
    recommendation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:category, @valid_categories,
      message: "must be one of: #{Enum.join(@valid_categories, ", ")}"
    )
    |> validate_inclusion(:price_range, ~w($ $$ $$$ $$$$))
    |> validate_number(:rating, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
  end
end
