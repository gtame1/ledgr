defmodule Ledgr.Domains.VolumeStudio.SubscriptionPlans do
  @moduledoc """
  Context module for managing Volume Studio subscription plans.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans.SubscriptionPlan

  @doc "Returns all subscription plans, ordered by price."
  def list_subscription_plans do
    SubscriptionPlan
    |> order_by(asc: :price_cents)
    |> Repo.all()
  end

  @doc "Returns only active subscription plans. Useful for select dropdowns."
  def list_active_subscription_plans do
    SubscriptionPlan
    |> where(active: true)
    |> order_by(asc: :price_cents)
    |> Repo.all()
  end

  @doc "Gets a single subscription plan. Raises if not found."
  def get_subscription_plan!(id), do: Repo.get!(SubscriptionPlan, id)

  @doc "Returns a changeset for the given plan and attrs."
  def change_subscription_plan(%SubscriptionPlan{} = plan, attrs \\ %{}) do
    SubscriptionPlan.changeset(plan, attrs)
  end

  @doc "Creates a subscription plan."
  def create_subscription_plan(attrs \\ %{}) do
    %SubscriptionPlan{}
    |> SubscriptionPlan.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a subscription plan."
  def update_subscription_plan(%SubscriptionPlan{} = plan, attrs) do
    plan
    |> SubscriptionPlan.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a subscription plan."
  def delete_subscription_plan(%SubscriptionPlan{} = plan) do
    Repo.delete(plan)
  end
end
