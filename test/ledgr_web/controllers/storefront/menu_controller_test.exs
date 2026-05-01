defmodule LedgrWeb.Storefront.MenuControllerTest do
  use LedgrWeb.ConnCase, async: true

  import Ledgr.Domains.MrMunchMe.OrdersFixtures

  describe "GET /mr-munch-me/menu (index)" do
    test "renders all active products when no search query given", %{conn: conn} do
      product1 = product_fixture(%{name: "Brownie Box", active: true})
      _variant1 = variant_fixture(%{product: product1, price_cents: 8000})
      product2 = product_fixture(%{name: "Cookie Box", active: true})
      _variant2 = variant_fixture(%{product: product2, price_cents: 6000})

      conn = get(conn, "/mr-munch-me/menu")

      assert html_response(conn, 200) =~ "Brownie Box"
      assert html_response(conn, 200) =~ "Cookie Box"
    end

    test "filters products by name with search query", %{conn: conn} do
      product1 = product_fixture(%{name: "Chocolate Brownie", active: true})
      _variant1 = variant_fixture(%{product: product1})
      product2 = product_fixture(%{name: "Vanilla Cookie", active: true})
      _variant2 = variant_fixture(%{product: product2})

      conn = get(conn, "/mr-munch-me/menu?q=brownie")

      body = html_response(conn, 200)
      assert body =~ "Chocolate Brownie"
      refute body =~ "Vanilla Cookie"
    end

    test "filters products by description with search query", %{conn: conn} do
      product1 =
        product_fixture(%{
          name: "Special Cake",
          description: "made with dark chocolate",
          active: true
        })

      _variant1 = variant_fixture(%{product: product1})

      product2 =
        product_fixture(%{name: "Fruit Tart", description: "fresh seasonal fruits", active: true})

      _variant2 = variant_fixture(%{product: product2})

      conn = get(conn, "/mr-munch-me/menu?q=chocolate")

      body = html_response(conn, 200)
      assert body =~ "Special Cake"
      refute body =~ "Fruit Tart"
    end

    test "search is case-insensitive", %{conn: conn} do
      product = product_fixture(%{name: "Carrot Cake", active: true})
      _variant = variant_fixture(%{product: product})

      conn = get(conn, "/mr-munch-me/menu?q=CARROT")

      assert html_response(conn, 200) =~ "Carrot Cake"
    end

    test "empty search string returns all products", %{conn: conn} do
      product1 = product_fixture(%{name: "Product A", active: true})
      _variant1 = variant_fixture(%{product: product1})
      product2 = product_fixture(%{name: "Product B", active: true})
      _variant2 = variant_fixture(%{product: product2})

      conn = get(conn, "/mr-munch-me/menu?q=")

      body = html_response(conn, 200)
      assert body =~ "Product A"
      assert body =~ "Product B"
    end

    test "returns 200 even when no products match the search", %{conn: conn} do
      conn = get(conn, "/mr-munch-me/menu?q=zzznomatch")
      assert html_response(conn, 200) =~ "zzznomatch"
    end
  end

  describe "GET /mr-munch-me/menu/:id (show)" do
    test "renders product detail page", %{conn: conn} do
      product = product_fixture(%{name: "Birthday Cake", description: "A lovely cake"})
      _variant = variant_fixture(%{product: product, name: "Grande", price_cents: 25000})

      conn = get(conn, "/mr-munch-me/menu/#{product.id}")

      body = html_response(conn, 200)
      assert body =~ "Birthday Cake"
      # Single-variant products don't render the variant name (hidden input only);
      # assert the description and price are rendered instead.
      assert body =~ "A lovely cake"
      assert body =~ "$250.00 MXN"
    end

    test "shows product with multiple variants", %{conn: conn} do
      product = product_fixture(%{name: "Cookie Box"})
      _v1 = variant_fixture(%{product: product, name: "Chico", price_cents: 5000})
      _v2 = variant_fixture(%{product: product, name: "Grande", price_cents: 8000})

      conn = get(conn, "/mr-munch-me/menu/#{product.id}")

      body = html_response(conn, 200)
      assert body =~ "Chico"
      assert body =~ "Grande"
    end

    test "shows product description rendered from markdown", %{conn: conn} do
      product = product_fixture(%{name: "Brownie", description: "**Rich** and fudgy"})
      _variant = variant_fixture(%{product: product})

      conn = get(conn, "/mr-munch-me/menu/#{product.id}")

      # Earmark renders **bold** as <strong>
      assert html_response(conn, 200) =~ "<strong>Rich</strong>"
    end

    test "raises for non-existent product id", %{conn: conn} do
      assert_error_sent(404, fn ->
        get(conn, "/mr-munch-me/menu/999999999")
      end)
    end
  end
end
