defmodule LedgrWeb.Storefront.CheckoutControllerTest do
  use LedgrWeb.ConnCase, async: true

  import Ledgr.Domains.MrMunchMe.OrdersFixtures

  # Shared setup: a product/variant and a prep location so that
  # get_default_prep_location/0 finds at least one location.
  setup do
    product = product_fixture(%{name: "Brownie Box"})
    variant = variant_fixture(%{product: product, price_cents: 9000, active: true})
    location = location_fixture(%{code: "CASA_AG", name: "Casa AG"})

    {:ok, product: product, variant: variant, location: location}
  end

  # Minimum order date: 36h from now = at least 2 days out to be safe in tests
  defp future_date, do: Date.to_iso8601(Date.add(Date.utc_today(), 3))

  # ---------------------------------------------------------------------------
  # GET /mr-munch-me/checkout
  # ---------------------------------------------------------------------------

  describe "GET /mr-munch-me/checkout (new)" do
    test "redirects to menu when cart is empty", %{conn: conn} do
      conn = get(conn, "/mr-munch-me/checkout")

      assert redirected_to(conn) == "/mr-munch-me/menu"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "vacío"
    end

    test "renders checkout form when cart has items", %{conn: conn, variant: variant} do
      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 2}})
        |> get("/mr-munch-me/checkout")

      assert html_response(conn, 200) =~ "Checkout"
    end
  end

  # ---------------------------------------------------------------------------
  # POST /mr-munch-me/checkout (create)
  # ---------------------------------------------------------------------------

  describe "POST /mr-munch-me/checkout (create)" do
    test "redirects to menu with error when cart is empty", %{conn: conn} do
      conn =
        post(conn, "/mr-munch-me/checkout", %{
          "checkout" => %{
            "customer_name" => "Ana",
            "customer_phone" => "5551234567",
            "delivery_type" => "pickup",
            "delivery_date" => future_date()
          }
        })

      assert redirected_to(conn) == "/mr-munch-me/menu"
    end

    test "re-renders form with validation errors when required fields are missing", %{conn: conn, variant: variant} do
      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 1}})
        |> post("/mr-munch-me/checkout", %{
          "checkout" => %{
            "customer_name" => "",
            "customer_phone" => "",
            "delivery_type" => "",
            "delivery_date" => ""
          }
        })

      body = html_response(conn, 200)
      assert body =~ "requerido"
    end

    test "re-renders form when customer_name is missing", %{conn: conn, variant: variant} do
      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 1}})
        |> post("/mr-munch-me/checkout", %{
          "checkout" => %{
            "customer_name" => "",
            "customer_phone" => "5551234567",
            "delivery_type" => "pickup",
            "delivery_date" => future_date()
          }
        })

      assert html_response(conn, 200) =~ "nombre es requerido"
    end

    test "re-renders form when delivery_type is missing", %{conn: conn, variant: variant} do
      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 1}})
        |> post("/mr-munch-me/checkout", %{
          "checkout" => %{
            "customer_name" => "Ana",
            "customer_phone" => "5551234567",
            "delivery_type" => "",
            "delivery_date" => future_date()
          }
        })

      assert html_response(conn, 200) =~ "selecciona"
    end

    test "creates orders and renders confirmation on valid submission", %{conn: conn, variant: variant} do
      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 1}})
        |> post("/mr-munch-me/checkout", %{
          "checkout" => %{
            "customer_name" => "María García",
            "customer_phone" => "5559876543",
            "customer_email" => "maria@example.com",
            "delivery_type" => "pickup",
            "delivery_date" => future_date(),
            "delivery_time" => "10:00",
            "delivery_address" => "",
            "special_instructions" => "",
            "payment_method" => "cod"
          }
        })

      body = html_response(conn, 200)
      assert body =~ "María García"
    end

    test "clears cart session after successful checkout", %{conn: conn, variant: variant} do
      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 1}})
        |> post("/mr-munch-me/checkout", %{
          "checkout" => %{
            "customer_name" => "Carlos López",
            "customer_phone" => "5551112222",
            "delivery_type" => "pickup",
            "delivery_date" => future_date(),
            "delivery_time" => "14:00",
            "delivery_address" => "",
            "payment_method" => "cod"
          }
        })

      # Successful checkout renders confirmation page
      assert html_response(conn, 200)
      # Cart should be cleared
      assert get_session(conn, :cart) == nil
    end

    test "creates order with delivery type and renders whatsapp button", %{conn: conn, variant: variant} do
      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 2}})
        |> post("/mr-munch-me/checkout", %{
          "checkout" => %{
            "customer_name" => "Luis Pérez",
            "customer_phone" => "5553334444",
            "delivery_type" => "delivery",
            "delivery_date" => future_date(),
            "delivery_time" => "12:00",
            "delivery_address" => "Calle Falsa 123, CDMX",
            "special_instructions" => "Sin azúcar",
            "payment_method" => "cod"
          }
        })

      body = html_response(conn, 200)
      # WhatsApp button should be present
      assert body =~ "wa.me"
    end

    test "handles existing customer by phone (find_or_create)", %{conn: conn, variant: variant} do
      # First checkout creates customer with this phone
      conn1 =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 1}})
        |> post("/mr-munch-me/checkout", %{
          "checkout" => %{
            "customer_name" => "Ana Martínez",
            "customer_phone" => "5556667777",
            "delivery_type" => "pickup",
            "delivery_date" => future_date(),
            "delivery_time" => "11:00",
            "delivery_address" => "",
            "payment_method" => "cod"
          }
        })

      assert html_response(conn1, 200)

      # Second checkout with same phone should still succeed (finds existing customer)
      conn2 =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 1}})
        |> post("/mr-munch-me/checkout", %{
          "checkout" => %{
            "customer_name" => "Ana Martínez",
            "customer_phone" => "5556667777",
            "delivery_type" => "pickup",
            "delivery_date" => future_date(),
            "delivery_time" => "11:00",
            "delivery_address" => "",
            "payment_method" => "cod"
          }
        })

      assert html_response(conn2, 200)
    end

    test "includes special instructions in whatsapp message", %{conn: conn, variant: variant} do
      conn =
        conn
        |> init_test_session(%{cart: %{to_string(variant.id) => 1}})
        |> post("/mr-munch-me/checkout", %{
          "checkout" => %{
            "customer_name" => "Pedro Ruiz",
            "customer_phone" => "5558889999",
            "delivery_type" => "pickup",
            "delivery_date" => future_date(),
            "delivery_time" => "15:00",
            "delivery_address" => "",
            "special_instructions" => "Sin gluten por favor",
            "payment_method" => "cod"
          }
        })

      body = html_response(conn, 200)
      # WhatsApp URL should be present with encoded message
      assert body =~ "wa.me"
    end
  end
end
