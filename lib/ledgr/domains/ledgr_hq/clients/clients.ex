defmodule Ledgr.Domains.LedgrHQ.Clients do
  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.LedgrHQ.Clients.Client

  def list_clients(opts \\ []) do
    status = Keyword.get(opts, :status)

    Client
    |> maybe_filter_status(status)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  def get_client!(id), do: Repo.get!(Client, id)

  def change_client(%Client{} = client, attrs \\ %{}) do
    Client.changeset(client, attrs)
  end

  def create_client(attrs \\ %{}) do
    %Client{}
    |> Client.changeset(attrs)
    |> Repo.insert()
  end

  def update_client(%Client{} = client, attrs) do
    client
    |> Client.changeset(attrs)
    |> Repo.update()
  end

  def delete_client(%Client{} = client) do
    Repo.delete(client)
  end

  @doc "Returns the list of domain slugs for all registered domains (for linking clients to apps)."
  def available_domain_slugs do
    Application.get_env(:ledgr, :domains, [])
    |> Enum.map(& &1.slug())
    |> Enum.reject(&(&1 == "ledgr"))
  end
end
