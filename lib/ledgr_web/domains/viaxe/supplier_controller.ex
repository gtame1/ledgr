defmodule LedgrWeb.Domains.Viaxe.SupplierController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.Viaxe.Suppliers
  alias Ledgr.Domains.Viaxe.Suppliers.Supplier

  def index(conn, _params) do
    suppliers = Suppliers.list_suppliers()
    render(conn, :index, suppliers: suppliers)
  end

  def new(conn, _params) do
    changeset = Suppliers.change_supplier(%Supplier{})
    render(conn, :new, changeset: changeset, action: dp(conn, "/suppliers"))
  end

  def create(conn, %{"supplier" => supplier_params}) do
    case Suppliers.create_supplier(supplier_params) do
      {:ok, _supplier} ->
        conn
        |> put_flash(:info, "Supplier created successfully.")
        |> redirect(to: dp(conn, "/suppliers"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, action: dp(conn, "/suppliers"))
    end
  end

  def show(conn, %{"id" => id}) do
    supplier = Suppliers.get_supplier!(id)
    render(conn, :show, supplier: supplier)
  end

  def edit(conn, %{"id" => id}) do
    supplier = Suppliers.get_supplier!(id)
    changeset = Suppliers.change_supplier(supplier)

    render(conn, :edit,
      supplier: supplier,
      changeset: changeset,
      action: dp(conn, "/suppliers/#{id}")
    )
  end

  def update(conn, %{"id" => id, "supplier" => supplier_params}) do
    supplier = Suppliers.get_supplier!(id)

    case Suppliers.update_supplier(supplier, supplier_params) do
      {:ok, _supplier} ->
        conn
        |> put_flash(:info, "Supplier updated successfully.")
        |> redirect(to: dp(conn, "/suppliers"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit,
          supplier: supplier,
          changeset: changeset,
          action: dp(conn, "/suppliers/#{id}")
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    supplier = Suppliers.get_supplier!(id)
    {:ok, _} = Suppliers.delete_supplier(supplier)

    conn
    |> put_flash(:info, "Supplier deleted successfully.")
    |> redirect(to: dp(conn, "/suppliers"))
  end
end

defmodule LedgrWeb.Domains.Viaxe.SupplierHTML do
  use LedgrWeb, :html

  embed_templates "supplier_html/*"
end
