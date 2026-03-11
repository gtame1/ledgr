defmodule LedgrWeb.Domains.VolumeStudio.SubscriptionController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.Subscriptions
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans
  alias Ledgr.Core.Customers

  def index(conn, params) do
    status = params["status"]
    subscriptions = Subscriptions.list_subscriptions(status: status)
    render(conn, :index, subscriptions: subscriptions, current_status: status)
  end

  def show(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)
    summary = Subscriptions.payment_summary(subscription)
    render(conn, :show, subscription: subscription, summary: summary)
  end

  def new(conn, _params) do
    changeset = Subscriptions.change_subscription(%Subscription{starts_on: Date.utc_today()})
    customers = customer_options()
    plans = SubscriptionPlans.list_active_subscription_plans()
    render(conn, :new,
      changeset: changeset,
      customers: customers,
      plans: plans,
      action: dp(conn, "/subscriptions")
    )
  end

  def create(conn, %{"subscription" => params}) do
    case Subscriptions.create_subscription(params) do
      {:ok, sub} ->
        conn
        |> put_flash(:info, "Subscription created successfully.")
        |> redirect(to: dp(conn, "/subscriptions/#{sub.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = customer_options()
        plans = SubscriptionPlans.list_active_subscription_plans()
        render(conn, :new,
          changeset: changeset,
          customers: customers,
          plans: plans,
          action: dp(conn, "/subscriptions")
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)
    changeset = Subscriptions.change_subscription(subscription)
    customers = customer_options()
    plans = SubscriptionPlans.list_active_subscription_plans()
    render(conn, :edit,
      subscription: subscription,
      changeset: changeset,
      customers: customers,
      plans: plans,
      action: dp(conn, "/subscriptions/#{id}")
    )
  end

  def update(conn, %{"id" => id, "subscription" => params}) do
    subscription = Subscriptions.get_subscription!(id)

    case Subscriptions.update_subscription(subscription, params) do
      {:ok, sub} ->
        conn
        |> put_flash(:info, "Subscription updated.")
        |> redirect(to: dp(conn, "/subscriptions/#{sub.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = customer_options()
        plans = SubscriptionPlans.list_active_subscription_plans()
        render(conn, :edit,
          subscription: subscription,
          changeset: changeset,
          customers: customers,
          plans: plans,
          action: dp(conn, "/subscriptions/#{id}")
        )
    end
  end

  def record_payment(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)

    case Subscriptions.record_payment(subscription) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Payment recorded and deferred revenue updated.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not record payment: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))
    end
  end

  def cancel(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)

    case Subscriptions.cancel(subscription) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Subscription cancelled.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not cancel subscription.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))
    end
  end

  defp customer_options do
    Customers.list_customers()
    |> Enum.map(&{"#{&1.name} (#{&1.phone})", &1.id})
  end
end

defmodule LedgrWeb.Domains.VolumeStudio.SubscriptionHTML do
  use LedgrWeb, :html

  embed_templates "subscription_html/*"

  def status_class("active"), do: "status-paid"
  def status_class("paused"), do: "status-partial"
  def status_class("cancelled"), do: "status-unpaid"
  def status_class("expired"), do: "status-unpaid"
  def status_class(_), do: ""
end
