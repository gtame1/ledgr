defmodule LedgrWeb.Domains.Viaxe.SupplierControllerTest do
  use LedgrWeb.ConnCase

  alias Ledgr.Domains.Viaxe.Suppliers

  setup %{conn: conn} do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)

    {:ok, user} =
      Ledgr.Core.Accounts.create_user(%{email: "viaxe@test.example", password: "password123!"})

    conn = Phoenix.ConnTest.init_test_session(conn, %{"user_id:viaxe" => user.id})

    {:ok, supplier} =
      Suppliers.create_supplier(%{
        name: "Aeromexico",
        category: "airline",
        country: "MX",
        city: "Mexico City"
      })

    {:ok, conn: conn, supplier: supplier}
  end

  describe "index/2" do
    test "lists all suppliers", %{conn: conn, supplier: supplier} do
      conn = get(conn, "/app/viaxe/suppliers")
      assert html_response(conn, 200) =~ supplier.name
    end
  end

  describe "show/2" do
    test "shows a supplier", %{conn: conn, supplier: supplier} do
      conn = get(conn, "/app/viaxe/suppliers/#{supplier.id}")
      assert html_response(conn, 200) =~ supplier.name
    end
  end

  describe "new/2" do
    test "renders new form", %{conn: conn} do
      conn = get(conn, "/app/viaxe/suppliers/new")
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "create/2" do
    test "creates supplier and redirects on valid params", %{conn: conn} do
      params = %{
        "supplier" => %{
          "name" => "Copa Airlines",
          "category" => "airline",
          "country" => "PA"
        }
      }

      conn = post(conn, "/app/viaxe/suppliers", params)
      assert redirected_to(conn) == "/app/viaxe/suppliers"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "created"
    end

    test "renders errors on invalid params", %{conn: conn} do
      params = %{"supplier" => %{"name" => ""}}
      conn = post(conn, "/app/viaxe/suppliers", params)
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "edit/2" do
    test "renders edit form", %{conn: conn, supplier: supplier} do
      conn = get(conn, "/app/viaxe/suppliers/#{supplier.id}/edit")
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "update/2" do
    test "updates supplier and redirects on valid params", %{conn: conn, supplier: supplier} do
      params = %{
        "supplier" => %{
          "name" => "Aeromexico Connect",
          "category" => "airline"
        }
      }

      conn = put(conn, "/app/viaxe/suppliers/#{supplier.id}", params)
      assert redirected_to(conn) == "/app/viaxe/suppliers"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "updated"
    end

    test "renders errors on invalid params", %{conn: conn, supplier: supplier} do
      params = %{"supplier" => %{"name" => ""}}
      conn = put(conn, "/app/viaxe/suppliers/#{supplier.id}", params)
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "delete/2" do
    test "deletes supplier and redirects", %{conn: conn, supplier: supplier} do
      conn = delete(conn, "/app/viaxe/suppliers/#{supplier.id}")
      assert redirected_to(conn) == "/app/viaxe/suppliers"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "deleted"
    end
  end
end
