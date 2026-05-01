defmodule Ledgr.Domains.LedgrHQ.ClientSubscriptions.ClientSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.LedgrHQ.Clients.Client
  alias Ledgr.Domains.LedgrHQ.SubscriptionPlans.SubscriptionPlan

  @valid_statuses ~w(active trial cancelled)

  schema "client_subscriptions" do
    belongs_to :client, Client
    belongs_to :subscription_plan, SubscriptionPlan

    field :starts_on, :date
    field :ends_on, :date
    field :status, :string, default: "active"
    field :price_override_cents, :integer
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:client_id, :subscription_plan_id, :starts_on, :status]
  @optional_fields [:ends_on, :price_override_cents, :notes]

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:price_override_cents, greater_than: 0)
    |> foreign_key_constraint(:client_id)
    |> foreign_key_constraint(:subscription_plan_id)
  end

  @doc "Returns the effective monthly price: override if set, otherwise the plan price."
  def effective_price_cents(%__MODULE__{price_override_cents: override, subscription_plan: _plan})
      when not is_nil(override),
      do: override

  def effective_price_cents(%__MODULE__{subscription_plan: %SubscriptionPlan{price_cents: p}}),
    do: p

  def effective_price_cents(_), do: 0
end
