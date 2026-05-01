defmodule Ledgr.Domains.VolumeStudio.SubscriptionPlans do
  @moduledoc """
  Context module for managing Volume Studio subscription plans.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans.SubscriptionPlan

  @doc "Returns all subscription plans, ordered by type then price. Pass `plan_type:` opt to filter by type."
  def list_subscription_plans(opts \\ []) do
    plan_type = Keyword.get(opts, :plan_type)

    SubscriptionPlan
    |> where([sp], is_nil(sp.deleted_at))
    |> maybe_filter_plan_type(plan_type)
    |> order_by([sp],
      asc:
        fragment(
          "CASE ? WHEN 'package' THEN 0 WHEN 'promo' THEN 1 WHEN 'membership' THEN 2 ELSE 3 END",
          sp.plan_type
        ),
      asc: sp.price_cents
    )
    |> Repo.all()
  end

  defp maybe_filter_plan_type(query, nil), do: query
  defp maybe_filter_plan_type(query, type), do: where(query, plan_type: ^type)

  @doc "Returns only active subscription plans. Useful for select dropdowns."
  def list_active_subscription_plans do
    SubscriptionPlan
    |> where([sp], sp.active == true and is_nil(sp.deleted_at))
    |> order_by([sp],
      asc:
        fragment(
          "CASE ? WHEN 'package' THEN 0 WHEN 'promo' THEN 1 WHEN 'membership' THEN 2 ELSE 3 END",
          sp.plan_type
        ),
      asc: sp.price_cents
    )
    |> Repo.all()
  end

  @doc "Returns only active extra-type plans, ordered by price. Used by Quick Sale."
  def list_active_extra_plans do
    SubscriptionPlan
    |> where([sp], sp.active == true and sp.plan_type == "extra" and is_nil(sp.deleted_at))
    |> order_by([sp], asc: sp.price_cents)
    |> Repo.all()
  end

  @doc "Gets a single subscription plan. Raises if not found."
  def get_subscription_plan!(id) do
    from(sp in SubscriptionPlan, where: sp.id == ^id and is_nil(sp.deleted_at))
    |> Repo.one!()
  end

  @doc "Gets a subscription plan by exact name, returns nil if not found."
  def get_plan_by_name(name) do
    from(sp in SubscriptionPlan, where: sp.name == ^name and is_nil(sp.deleted_at))
    |> Repo.one()
  end

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

  @doc "Soft-deletes a subscription plan. Always succeeds — plans are archived, not hard-deleted."
  def delete_subscription_plan(%SubscriptionPlan{} = plan) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    plan
    |> Ecto.Changeset.change(deleted_at: now)
    |> Repo.update()
  end
end
