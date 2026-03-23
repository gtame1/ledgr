defmodule Ledgr.Domains.LedgrHQ.SubscriptionPlans.SubscriptionPlan do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscription_plans" do
    field :name, :string
    field :description, :string
    field :price_cents, :integer
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :price_cents]
  @optional_fields [:description, :active]

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:price_cents, greater_than: 0)
  end
end
