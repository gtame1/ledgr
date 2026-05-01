defmodule LedgrWeb.CustomerController do
  use LedgrWeb, :controller

  alias Ledgr.Core.Customers
  alias Ledgr.Core.Customers.Customer
  alias Ledgr.Domains.VolumeStudio.Subscriptions

  def index(conn, _params) do
    customers = Customers.list_customers()
    render(conn, :index, customers: customers)
  end

  def show(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)
    subscriptions = Subscriptions.list_subscriptions(customer_id: id)
    render(conn, :show, customer: customer, subscriptions: subscriptions)
  end

  def api_show(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)

    json(conn, %{
      id: customer.id,
      name: customer.name,
      phone: customer.phone,
      email: customer.email,
      delivery_address: customer.delivery_address
    })
  end

  def new(conn, _params) do
    changeset = Customers.change_customer(%Customer{})
    render(conn, :new, changeset: changeset, action: dp(conn, "/customers"))
  end

  def create(conn, %{"customer" => customer_params}) do
    case Customers.create_customer(customer_params) do
      {:ok, customer} ->
        conn
        |> put_flash(:info, "Customer created successfully.")
        |> redirect(to: dp(conn, "/customers/#{customer.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :insert)
        render(conn, :new, changeset: changeset, action: dp(conn, "/customers"))
    end
  end

  def edit(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)
    changeset = Customers.change_customer(customer)

    render(conn, :edit,
      customer: customer,
      changeset: changeset,
      action: dp(conn, "/customers/#{customer.id}")
    )
  end

  def update(conn, %{"id" => id, "customer" => customer_params}) do
    customer = Customers.get_customer!(id)

    case Customers.update_customer(customer, customer_params) do
      {:ok, customer} ->
        conn
        |> put_flash(:info, "Customer updated successfully.")
        |> redirect(to: dp(conn, "/customers/#{customer.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :update)

        render(conn, :edit,
          customer: customer,
          changeset: changeset,
          action: dp(conn, "/customers/#{customer.id}")
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)

    case Customers.delete_customer(customer) do
      {:ok, _customer} ->
        conn
        |> put_flash(:info, "Customer deleted successfully.")
        |> redirect(to: dp(conn, "/customers"))

      {:error, :has_active_orders} ->
        conn
        |> put_flash(
          :error,
          "Cannot delete customer. This customer has active orders or bookings. Please cancel or complete them first."
        )
        |> redirect(to: dp(conn, "/customers/#{customer.id}"))
    end
  end
end

defmodule LedgrWeb.CustomerHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents

  embed_templates "customer_html/*"
end
