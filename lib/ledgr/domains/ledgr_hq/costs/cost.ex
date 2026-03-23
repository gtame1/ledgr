defmodule Ledgr.Domains.LedgrHQ.Costs.Cost do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_categories ~w(cloud_hosting domain_dns saas_tools)
  @valid_billing_periods ~w(monthly annual one_time)

  schema "costs" do
    field :name, :string
    field :vendor, :string
    field :category, :string
    field :amount_cents, :integer
    field :billing_period, :string, default: "monthly"
    field :active, :boolean, default: true
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :category, :amount_cents, :billing_period]
  @optional_fields [:vendor, :active, :notes]

  def changeset(cost, attrs) do
    cost
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:category, @valid_categories)
    |> validate_inclusion(:billing_period, @valid_billing_periods)
    |> validate_number(:amount_cents, greater_than: 0)
  end

  @doc "Returns the normalized monthly cost in cents."
  def monthly_cents(%__MODULE__{billing_period: "annual", amount_cents: a}), do: div(a, 12)
  def monthly_cents(%__MODULE__{billing_period: "one_time", amount_cents: _}), do: 0
  def monthly_cents(%__MODULE__{amount_cents: a}), do: a

  def category_label("cloud_hosting"), do: "Cloud & Hosting"
  def category_label("domain_dns"), do: "Domains & DNS"
  def category_label("saas_tools"), do: "SaaS & Tools"
  def category_label(other), do: String.capitalize(other || "")
end
