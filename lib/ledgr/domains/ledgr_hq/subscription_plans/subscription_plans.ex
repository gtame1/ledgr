defmodule Ledgr.Domains.LedgrHQ.SubscriptionPlans do
  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.LedgrHQ.SubscriptionPlans.SubscriptionPlan

  def list_subscription_plans do
    SubscriptionPlan
    |> order_by([sp], asc: sp.price_cents)
    |> Repo.all()
  end

  def list_active_subscription_plans do
    SubscriptionPlan
    |> where([sp], sp.active == true)
    |> order_by([sp], asc: sp.price_cents)
    |> Repo.all()
  end

  def get_subscription_plan!(id), do: Repo.get!(SubscriptionPlan, id)

  def change_subscription_plan(%SubscriptionPlan{} = plan, attrs \\ %{}) do
    SubscriptionPlan.changeset(plan, attrs)
  end

  def create_subscription_plan(attrs \\ %{}) do
    %SubscriptionPlan{}
    |> SubscriptionPlan.changeset(attrs)
    |> Repo.insert()
  end

  def update_subscription_plan(%SubscriptionPlan{} = plan, attrs) do
    plan
    |> SubscriptionPlan.changeset(attrs)
    |> Repo.update()
  end

  def delete_subscription_plan(%SubscriptionPlan{} = plan) do
    Repo.delete(plan)
  end
end
