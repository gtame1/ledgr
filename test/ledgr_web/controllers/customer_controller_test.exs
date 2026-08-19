defmodule LedgrWeb.CustomerControllerTest do
  @moduledoc """
  `CustomerController` is shared, but MrMunchMe is now its only consumer.

  It used to call `Ledgr.Domains.VolumeStudio.Subscriptions.list_subscriptions/1`
  unconditionally in `show/2` and render the result — so deleting Volume Studio
  would have taken MrMunchMe's customer page down with it. These tests exist
  because the page had no coverage at all when that dependency was removed.
  """
  use LedgrWeb.ConnCase

  import Ledgr.Core.CustomersFixtures

  setup %{conn: conn} do
    {:ok, conn: log_in_user(conn)}
  end

  describe "GET /customers" do
    test "lists customers", %{conn: conn} do
      customer_fixture(%{name: "Ada Lovelace"})

      assert conn |> get("/app/mr-munch-me/customers") |> html_response(200) =~ "Ada Lovelace"
    end

    test "renders with no customers", %{conn: conn} do
      assert conn |> get("/app/mr-munch-me/customers") |> html_response(200)
    end
  end

  describe "GET /customers/:id" do
    test "renders the customer without a Subscriptions section", %{conn: conn} do
      customer = customer_fixture(%{name: "Grace Hopper", email: "grace@example.com"})

      html = conn |> get("/app/mr-munch-me/customers/#{customer.id}") |> html_response(200)

      assert html =~ "Grace Hopper"
      assert html =~ "grace@example.com"

      # The section came from Volume Studio, which no longer exists.
      refute html =~ "Subscriptions"
      refute html =~ "New Subscription"
    end
  end
end
