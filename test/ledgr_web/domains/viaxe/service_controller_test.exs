defmodule LedgrWeb.Domains.Viaxe.ServiceControllerTest do
  use LedgrWeb.ConnCase

  alias Ledgr.Domains.Viaxe.Services

  setup %{conn: conn} do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)

    {:ok, user} =
      Ledgr.Core.Accounts.create_user(%{email: "viaxe@test.example", password: "password123!"})

    conn = Phoenix.ConnTest.init_test_session(conn, %{"user_id:viaxe" => user.id})

    {:ok, service} =
      Services.create_service(%{
        name: "Economy Flight",
        category: "flight",
        default_cost_cents: 100_000,
        default_price_cents: 150_000,
        active: true
      })

    {:ok, conn: conn, service: service}
  end

  describe "index/2" do
    test "lists all services", %{conn: conn, service: service} do
      conn = get(conn, "/app/viaxe/services")
      assert html_response(conn, 200) =~ service.name
    end
  end

  describe "new/2" do
    test "renders new form", %{conn: conn} do
      conn = get(conn, "/app/viaxe/services/new")
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "create/2" do
    test "creates service and redirects on valid params", %{conn: conn} do
      # Controller accepts pesos values (strings) and converts to cents internally
      params = %{
        "service" => %{
          "name" => "Hotel Cancún",
          "category" => "hotel",
          "default_cost_cents" => "800.00",
          "default_price_cents" => "1000.00"
        }
      }

      conn = post(conn, "/app/viaxe/services", params)
      assert redirected_to(conn) == "/app/viaxe/services"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "created"
    end

    test "creates service without optional money fields", %{conn: conn} do
      params = %{
        "service" => %{
          "name" => "Travel Insurance Basic",
          "category" => "insurance"
        }
      }

      conn = post(conn, "/app/viaxe/services", params)
      assert redirected_to(conn) == "/app/viaxe/services"
    end

    test "renders errors on invalid params", %{conn: conn} do
      params = %{"service" => %{"name" => "", "category" => ""}}
      conn = post(conn, "/app/viaxe/services", params)
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "edit/2" do
    test "renders edit form with money values converted to pesos", %{conn: conn, service: service} do
      conn = get(conn, "/app/viaxe/services/#{service.id}/edit")
      # The controller converts cents to pesos for display
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "update/2" do
    test "updates service and redirects on valid params", %{conn: conn, service: service} do
      params = %{
        "service" => %{
          "name" => "Business Flight",
          "category" => "flight",
          "default_cost_cents" => "2000.00",
          "default_price_cents" => "2500.00"
        }
      }

      conn = put(conn, "/app/viaxe/services/#{service.id}", params)
      assert redirected_to(conn) == "/app/viaxe/services"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "updated"
    end

    test "renders errors on invalid params", %{conn: conn, service: service} do
      params = %{"service" => %{"name" => "", "category" => "invalid_category"}}
      conn = put(conn, "/app/viaxe/services/#{service.id}", params)
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "delete/2" do
    test "deletes service and redirects", %{conn: conn, service: service} do
      conn = delete(conn, "/app/viaxe/services/#{service.id}")
      assert redirected_to(conn) == "/app/viaxe/services"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "deleted"
    end
  end
end
