defmodule LedgrWeb.Domains.VolumeStudio.SubscriptionPlanController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans
  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans.SubscriptionPlan
  alias LedgrWeb.Helpers.MoneyHelper

  @valid_plan_types ~w(package promo membership extra)

  def index(conn, params) do
    current_plan_type = if params["type"] in @valid_plan_types, do: params["type"], else: nil
    plans = SubscriptionPlans.list_subscription_plans(plan_type: current_plan_type)
    render(conn, :index, plans: plans, current_plan_type: current_plan_type)
  end

  def new(conn, _params) do
    changeset = SubscriptionPlans.change_subscription_plan(%SubscriptionPlan{})
    render(conn, :new, changeset: changeset, action: dp(conn, "/subscription-plans"))
  end

  def create(conn, %{"subscription_plan" => params}) do
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:price_cents])

    case SubscriptionPlans.create_subscription_plan(params) do
      {:ok, _plan} ->
        conn
        |> put_flash(:info, "Subscription plan created successfully.")
        |> redirect(to: dp(conn, "/subscription-plans"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, action: dp(conn, "/subscription-plans"))
    end
  end

  def edit(conn, %{"id" => id}) do
    plan = SubscriptionPlans.get_subscription_plan!(id)
    attrs = %{"price_cents" => MoneyHelper.cents_to_pesos(plan.price_cents)}
    changeset = SubscriptionPlans.change_subscription_plan(plan, attrs)

    render(conn, :edit,
      plan: plan,
      changeset: changeset,
      action: dp(conn, "/subscription-plans/#{id}")
    )
  end

  def update(conn, %{"id" => id, "subscription_plan" => params}) do
    plan = SubscriptionPlans.get_subscription_plan!(id)
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:price_cents])

    case SubscriptionPlans.update_subscription_plan(plan, params) do
      {:ok, _plan} ->
        conn
        |> put_flash(:info, "Subscription plan updated successfully.")
        |> redirect(to: dp(conn, "/subscription-plans"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit,
          plan: plan,
          changeset: changeset,
          action: dp(conn, "/subscription-plans/#{id}")
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    plan = SubscriptionPlans.get_subscription_plan!(id)

    case SubscriptionPlans.delete_subscription_plan(plan) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Plan deleted.")
        |> redirect(to: dp(conn, "/subscription-plans"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Cannot delete this plan — active subscriptions reference it.")
        |> redirect(to: dp(conn, "/subscription-plans"))
    end
  end
end

defmodule LedgrWeb.Domains.VolumeStudio.SubscriptionPlanHTML do
  use LedgrWeb, :html

  embed_templates "subscription_plan_html/*"

  def plan_type_class("package"), do: "status-partial"
  def plan_type_class("promo"), do: "status-promo"
  def plan_type_class("membership"), do: "status-paid"
  def plan_type_class("extra"), do: "status-extra"
  def plan_type_class(_), do: ""
end
