defmodule LedgrWeb.Domains.LedgrHQ.SubscriptionPlanController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.LedgrHQ.SubscriptionPlans
  alias Ledgr.Domains.LedgrHQ.SubscriptionPlans.SubscriptionPlan
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, _params) do
    plans = SubscriptionPlans.list_subscription_plans()
    render(conn, :index, plans: plans)
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
        |> put_flash(:info, "Plan created.")
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
        |> put_flash(:info, "Plan updated.")
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
        |> put_flash(:error, "Cannot delete — active subscriptions reference this plan.")
        |> redirect(to: dp(conn, "/subscription-plans"))
    end
  end
end

defmodule LedgrWeb.Domains.LedgrHQ.SubscriptionPlanHTML do
  use LedgrWeb, :html

  embed_templates "subscription_plan_html/*"
end
