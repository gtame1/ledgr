defmodule Ledgr.Domains.Viaxe.Suppliers do
  @moduledoc """
  Context module for managing travel suppliers.
  """

  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Domains.Viaxe.Suppliers.Supplier

  def list_suppliers do
    Supplier
    |> order_by(asc: :name)
    |> Repo.all()
  end

  def get_supplier!(id), do: Repo.get!(Supplier, id)

  def create_supplier(attrs \\ %{}) do
    %Supplier{}
    |> Supplier.changeset(attrs)
    |> Repo.insert()
  end

  def update_supplier(%Supplier{} = supplier, attrs) do
    supplier
    |> Supplier.changeset(attrs)
    |> Repo.update()
  end

  def delete_supplier(%Supplier{} = supplier) do
    Repo.delete(supplier)
  end

  def change_supplier(%Supplier{} = supplier, attrs \\ %{}) do
    Supplier.changeset(supplier, attrs)
  end

  def supplier_select_options do
    Supplier
    |> order_by(asc: :name)
    |> select([s], {s.name, s.id})
    |> Repo.all()
  end
end
