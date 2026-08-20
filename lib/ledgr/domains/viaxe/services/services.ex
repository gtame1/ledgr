defmodule Ledgr.Domains.Viaxe.Services do
  @moduledoc """
  Context module for managing travel services.
  """

  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Domains.Viaxe.Services.Service

  def list_services do
    Service
    |> order_by(asc: :name)
    |> Repo.all()
  end

  def list_active_services do
    Service
    |> where(active: true)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  def get_service!(id), do: Repo.get!(Service, id)

  def create_service(attrs \\ %{}) do
    %Service{}
    |> Service.changeset(attrs)
    |> Repo.insert()
  end

  def update_service(%Service{} = service, attrs) do
    service
    |> Service.changeset(attrs)
    |> Repo.update()
  end

  def delete_service(%Service{} = service) do
    Repo.delete(service)
  end

  def change_service(%Service{} = service, attrs \\ %{}) do
    Service.changeset(service, attrs)
  end

  def service_select_options do
    Service
    |> where(active: true)
    |> order_by(asc: :name)
    |> select([s], {s.name, s.id})
    |> Repo.all()
  end
end
