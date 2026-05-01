defmodule LedgrWeb.Domains.Viaxe.ServiceController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.Viaxe.Services
  alias Ledgr.Domains.Viaxe.Services.Service
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, _params) do
    services = Services.list_services()
    render(conn, :index, services: services)
  end

  def new(conn, _params) do
    changeset = Services.change_service(%Service{})
    render(conn, :new, changeset: changeset, action: dp(conn, "/services"))
  end

  def create(conn, %{"service" => service_params}) do
    service_params =
      MoneyHelper.convert_params_pesos_to_cents(service_params, [
        :default_cost_cents,
        :default_price_cents
      ])

    case Services.create_service(service_params) do
      {:ok, _service} ->
        conn
        |> put_flash(:info, "Service created successfully.")
        |> redirect(to: dp(conn, "/services"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, action: dp(conn, "/services"))
    end
  end

  def edit(conn, %{"id" => id}) do
    service = Services.get_service!(id)

    attrs = %{
      "default_cost_cents" => MoneyHelper.cents_to_pesos(service.default_cost_cents || 0),
      "default_price_cents" => MoneyHelper.cents_to_pesos(service.default_price_cents || 0)
    }

    changeset = Services.change_service(service, attrs)

    render(conn, :edit,
      service: service,
      changeset: changeset,
      action: dp(conn, "/services/#{id}")
    )
  end

  def update(conn, %{"id" => id, "service" => service_params}) do
    service = Services.get_service!(id)

    service_params =
      MoneyHelper.convert_params_pesos_to_cents(service_params, [
        :default_cost_cents,
        :default_price_cents
      ])

    case Services.update_service(service, service_params) do
      {:ok, _service} ->
        conn
        |> put_flash(:info, "Service updated successfully.")
        |> redirect(to: dp(conn, "/services"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit,
          service: service,
          changeset: changeset,
          action: dp(conn, "/services/#{id}")
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    service = Services.get_service!(id)
    {:ok, _} = Services.delete_service(service)

    conn
    |> put_flash(:info, "Service deleted successfully.")
    |> redirect(to: dp(conn, "/services"))
  end
end

defmodule LedgrWeb.Domains.Viaxe.ServiceHTML do
  use LedgrWeb, :html

  embed_templates "service_html/*"
end
