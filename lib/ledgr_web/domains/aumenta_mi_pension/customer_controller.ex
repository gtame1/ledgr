defmodule LedgrWeb.Domains.AumentaMiPension.CustomerController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.Customers

  def index(conn, params) do
    customers = Customers.list_customers(search: params["search"])

    render(conn, :index,
      customers: customers,
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)

    render(conn, :show, customer: customer)
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.CustomerHTML do
  use LedgrWeb, :html
  embed_templates "customer_html/*"
end
