defmodule LedgrWeb.Domains.LedgrHQ.ClientController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.LedgrHQ.Clients
  alias Ledgr.Domains.LedgrHQ.Clients.Client

  @valid_statuses ~w(active trial paused churned)

  def index(conn, params) do
    status = if params["status"] in @valid_statuses, do: params["status"], else: nil
    clients = Clients.list_clients(status: status)
    render(conn, :index, clients: clients, current_status: status)
  end

  def show(conn, %{"id" => id}) do
    client = Clients.get_client!(id)
    render(conn, :show, client: client)
  end

  def new(conn, _params) do
    changeset = Clients.change_client(%Client{})
    domain_slugs = Clients.available_domain_slugs()
    render(conn, :new, changeset: changeset, action: dp(conn, "/clients"), domain_slugs: domain_slugs)
  end

  def create(conn, %{"client" => params}) do
    case Clients.create_client(params) do
      {:ok, client} ->
        conn
        |> put_flash(:info, "Client created.")
        |> redirect(to: dp(conn, "/clients/#{client.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        domain_slugs = Clients.available_domain_slugs()
        render(conn, :new, changeset: changeset, action: dp(conn, "/clients"), domain_slugs: domain_slugs)
    end
  end

  def edit(conn, %{"id" => id}) do
    client = Clients.get_client!(id)
    changeset = Clients.change_client(client)
    domain_slugs = Clients.available_domain_slugs()
    render(conn, :edit, client: client, changeset: changeset, action: dp(conn, "/clients/#{id}"), domain_slugs: domain_slugs)
  end

  def update(conn, %{"id" => id, "client" => params}) do
    client = Clients.get_client!(id)

    case Clients.update_client(client, params) do
      {:ok, client} ->
        conn
        |> put_flash(:info, "Client updated.")
        |> redirect(to: dp(conn, "/clients/#{client.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        domain_slugs = Clients.available_domain_slugs()
        render(conn, :edit, client: client, changeset: changeset, action: dp(conn, "/clients/#{id}"), domain_slugs: domain_slugs)
    end
  end

  def delete(conn, %{"id" => id}) do
    client = Clients.get_client!(id)
    {:ok, _} = Clients.delete_client(client)

    conn
    |> put_flash(:info, "Client deleted.")
    |> redirect(to: dp(conn, "/clients"))
  end

  def update_status(conn, %{"id" => id, "status" => status}) do
    client = Clients.get_client!(id)
    attrs = if status == "churned", do: %{"status" => status, "ended_on" => Date.utc_today()}, else: %{"status" => status}

    case Clients.update_client(client, attrs) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Client status updated.")
        |> redirect(to: dp(conn, "/clients/#{id}"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not update status.")
        |> redirect(to: dp(conn, "/clients/#{id}"))
    end
  end
end

defmodule LedgrWeb.Domains.LedgrHQ.ClientHTML do
  use LedgrWeb, :html

  embed_templates "client_html/*"

  def status_class("active"),  do: "status-paid"
  def status_class("trial"),   do: "status-partial"
  def status_class("paused"),  do: "status-unpaid"
  def status_class("churned"), do: "status-cancelled"
  def status_class(_),         do: ""
end
