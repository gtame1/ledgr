defmodule LedgrWeb.Domains.LedgrHQ.ClientSubscriptionController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.LedgrHQ.ClientSubscriptions
  alias Ledgr.Domains.LedgrHQ.ClientSubscriptions.ClientSubscription
  alias Ledgr.Domains.LedgrHQ.Clients
  alias Ledgr.Domains.LedgrHQ.SubscriptionPlans
  alias LedgrWeb.Helpers.MoneyHelper

  @valid_statuses ~w(active trial cancelled)

  def index(conn, params) do
    status = if params["status"] in @valid_statuses, do: params["status"], else: nil
    subs = ClientSubscriptions.list_client_subscriptions(status: status)
    render(conn, :index, subs: subs, current_status: status)
  end

  def show(conn, %{"id" => id}) do
    sub = ClientSubscriptions.get_client_subscription!(id)
    render(conn, :show, sub: sub)
  end

  def new(conn, _params) do
    changeset = ClientSubscriptions.change_client_subscription(%ClientSubscription{})
    clients = Clients.list_clients()
    plans = SubscriptionPlans.list_active_subscription_plans()
    render(conn, :new,
      changeset: changeset,
      action: dp(conn, "/client-subscriptions"),
      clients: clients,
      plans: plans
    )
  end

  def create(conn, %{"client_subscription" => params}) do
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:price_override_cents])

    case ClientSubscriptions.create_client_subscription(params) do
      {:ok, sub} ->
        conn
        |> put_flash(:info, "Subscription created.")
        |> redirect(to: dp(conn, "/client-subscriptions/#{sub.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        clients = Clients.list_clients()
        plans = SubscriptionPlans.list_active_subscription_plans()
        render(conn, :new,
          changeset: changeset,
          action: dp(conn, "/client-subscriptions"),
          clients: clients,
          plans: plans
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    sub = ClientSubscriptions.get_client_subscription!(id)
    attrs = if sub.price_override_cents, do: %{"price_override_cents" => MoneyHelper.cents_to_pesos(sub.price_override_cents)}, else: %{}
    changeset = ClientSubscriptions.change_client_subscription(sub, attrs)
    clients = Clients.list_clients()
    plans = SubscriptionPlans.list_active_subscription_plans()
    render(conn, :edit,
      sub: sub,
      changeset: changeset,
      action: dp(conn, "/client-subscriptions/#{id}"),
      clients: clients,
      plans: plans
    )
  end

  def update(conn, %{"id" => id, "client_subscription" => params}) do
    sub = ClientSubscriptions.get_client_subscription!(id)
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:price_override_cents])

    case ClientSubscriptions.update_client_subscription(sub, params) do
      {:ok, sub} ->
        conn
        |> put_flash(:info, "Subscription updated.")
        |> redirect(to: dp(conn, "/client-subscriptions/#{sub.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        clients = Clients.list_clients()
        plans = SubscriptionPlans.list_active_subscription_plans()
        render(conn, :edit,
          sub: sub,
          changeset: changeset,
          action: dp(conn, "/client-subscriptions/#{id}"),
          clients: clients,
          plans: plans
        )
    end
  end

  def update_status(conn, %{"id" => id, "status" => status}) do
    sub = ClientSubscriptions.get_client_subscription!(id)

    case ClientSubscriptions.update_client_subscription(sub, %{"status" => status}) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Status updated.")
        |> redirect(to: dp(conn, "/client-subscriptions/#{id}"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not update status.")
        |> redirect(to: dp(conn, "/client-subscriptions/#{id}"))
    end
  end
end

defmodule LedgrWeb.Domains.LedgrHQ.ClientSubscriptionHTML do
  use LedgrWeb, :html

  embed_templates "client_subscription_html/*"

  def status_class("active"),    do: "status-paid"
  def status_class("trial"),     do: "status-partial"
  def status_class("cancelled"), do: "status-cancelled"
  def status_class(_),           do: ""
end
