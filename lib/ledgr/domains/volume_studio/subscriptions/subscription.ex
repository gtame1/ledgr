defmodule Ledgr.Domains.VolumeStudio.Subscriptions.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Customers.Customer
  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans.SubscriptionPlan
  alias Ledgr.Domains.VolumeStudio.PartnerSplits.PartnerSplit

  schema "subscriptions" do
    belongs_to :customer, Customer
    belongs_to :subscription_plan, SubscriptionPlan
    belongs_to :partner_split, PartnerSplit

    field :starts_on, :date
    field :ends_on, :date
    field :status, :string, default: "active"
    field :classes_used, :integer, default: 0
    field :deferred_revenue_cents, :integer, default: 0
    field :recognized_revenue_cents, :integer, default: 0
    field :discount_cents, :integer, default: 0
    field :iva_cents, :integer, default: 0
    field :paid_cents, :integer, default: 0
    field :notes, :string
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields [:customer_id, :subscription_plan_id, :starts_on, :ends_on]
  @optional_fields [
    :status,
    :classes_used,
    :deferred_revenue_cents,
    :recognized_revenue_cents,
    :discount_cents,
    :iva_cents,
    :paid_cents,
    :notes,
    :partner_split_id
  ]

  @valid_statuses ~w(active paused cancelled expired completed)

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:discount_cents, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:subscription_plan_id)
  end

  @doc "Total amount paid into this subscription (deferred + recognized)"
  def total_paid_cents(%__MODULE__{} = sub) do
    sub.deferred_revenue_cents + sub.recognized_revenue_cents
  end

  @doc "Remaining deferred revenue not yet recognized"
  def remaining_deferred(%__MODULE__{} = sub) do
    max(sub.deferred_revenue_cents, 0)
  end

  @doc "Monthly recognition amount based on plan duration and any discount applied"
  def monthly_recognition_amount(%__MODULE__{} = sub) do
    plan = sub.subscription_plan

    if plan && plan.duration_months > 0 do
      effective = max(plan.price_cents - (sub.discount_cents || 0), 0)
      div(effective, plan.duration_months)
    else
      0
    end
  end
end
