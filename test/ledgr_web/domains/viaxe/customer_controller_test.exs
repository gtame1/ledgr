defmodule LedgrWeb.Domains.Viaxe.CustomerControllerTest do
  use LedgrWeb.ConnCase

  alias Ledgr.Domains.Viaxe.Customers
  alias Ledgr.Domains.Viaxe.TravelDocuments

  setup %{conn: conn} do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)

    {:ok, user} =
      Ledgr.Core.Accounts.create_user(%{email: "viaxe@test.example", password: "password123!"})

    conn = Phoenix.ConnTest.init_test_session(conn, %{"user_id:viaxe" => user.id})

    {:ok, customer} =
      Customers.create_customer(%{
        first_name: "Ana",
        last_name: "García",
        phone: "+525512345678"
      })

    {:ok, conn: conn, customer: customer}
  end

  # ── CustomerController ──────────────────────────────────────────────────────

  describe "index/2" do
    test "lists all customers", %{conn: conn, customer: customer} do
      conn = get(conn, "/app/viaxe/customers")
      assert html_response(conn, 200) =~ customer.last_name
    end
  end

  describe "show/2" do
    test "shows a customer with their travel documents", %{conn: conn, customer: customer} do
      conn = get(conn, "/app/viaxe/customers/#{customer.id}")
      assert html_response(conn, 200) =~ customer.first_name
    end
  end

  describe "new/2" do
    test "renders new customer form", %{conn: conn} do
      conn = get(conn, "/app/viaxe/customers/new")
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "create/2" do
    test "creates customer and redirects on valid params", %{conn: conn} do
      params = %{
        "customer" => %{
          "first_name" => "Carlos",
          "last_name" => "López",
          "phone" => "+525598765432",
          "email" => "carlos@example.com"
        }
      }

      conn = post(conn, "/app/viaxe/customers", params)
      assert redirected_to(conn) =~ "/app/viaxe/customers/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "created"
    end

    test "creates customer with travel profile", %{conn: conn} do
      params = %{
        "customer" => %{
          "first_name" => "María",
          "last_name" => "Pérez",
          "phone" => "+525511112222",
          "travel_profile" => %{
            "nationality" => "MX",
            "preferred_airline" => "Aeromexico"
          }
        }
      }

      conn = post(conn, "/app/viaxe/customers", params)
      assert redirected_to(conn) =~ "/app/viaxe/customers/"
    end

    test "renders errors on invalid params (missing required fields)", %{conn: conn} do
      params = %{"customer" => %{"first_name" => "", "last_name" => "", "phone" => ""}}
      conn = post(conn, "/app/viaxe/customers", params)
      assert html_response(conn, 200) =~ "form"
    end

    test "renders errors on duplicate phone number", %{conn: conn} do
      params = %{
        "customer" => %{
          "first_name" => "Duplicate",
          "last_name" => "Person",
          # Same phone as the setup customer
          "phone" => "+525512345678"
        }
      }

      conn = post(conn, "/app/viaxe/customers", params)
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "edit/2" do
    test "renders edit form", %{conn: conn, customer: customer} do
      conn = get(conn, "/app/viaxe/customers/#{customer.id}/edit")
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "update/2" do
    test "updates customer and redirects on valid params", %{conn: conn, customer: customer} do
      params = %{
        "customer" => %{
          "first_name" => "Ana María",
          "last_name" => "García Sánchez",
          "phone" => "+525512345678"
        }
      }

      conn = put(conn, "/app/viaxe/customers/#{customer.id}", params)
      assert redirected_to(conn) == "/app/viaxe/customers/#{customer.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "updated"
    end

    test "renders errors on invalid params", %{conn: conn, customer: customer} do
      params = %{"customer" => %{"first_name" => "", "last_name" => "", "phone" => ""}}
      conn = put(conn, "/app/viaxe/customers/#{customer.id}", params)
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "delete/2" do
    test "deletes customer and redirects", %{conn: conn, customer: customer} do
      conn = delete(conn, "/app/viaxe/customers/#{customer.id}")
      assert redirected_to(conn) == "/app/viaxe/customers"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "deleted"
    end
  end

  # ── PassportController (nested under customers) ─────────────────────────────

  describe "PassportController create/2" do
    test "adds passport to customer and redirects", %{conn: conn, customer: customer} do
      params = %{
        "passport" => %{
          "country" => "MX",
          "number" => "G01234567",
          "expiry_date" => "2030-01-15"
        }
      }

      conn = post(conn, "/app/viaxe/customers/#{customer.id}/passports", params)
      assert redirected_to(conn) == "/app/viaxe/customers/#{customer.id}"
    end
  end

  describe "PassportController delete/2" do
    test "removes passport from customer and redirects", %{conn: conn, customer: customer} do
      {:ok, passport} =
        TravelDocuments.create_passport(%{
          customer_id: customer.id,
          country: "MX",
          number: "G09876543"
        })

      conn =
        delete(conn, "/app/viaxe/customers/#{customer.id}/passports/#{passport.id}")

      assert redirected_to(conn) == "/app/viaxe/customers/#{customer.id}"
    end
  end

  # ── VisaController (nested under customers) ──────────────────────────────────

  describe "VisaController create/2" do
    test "adds visa to customer and redirects", %{conn: conn, customer: customer} do
      params = %{
        "visa" => %{
          "country" => "US",
          "visa_type" => "tourist",
          "expiry_date" => "2027-06-30"
        }
      }

      conn = post(conn, "/app/viaxe/customers/#{customer.id}/visas", params)
      assert redirected_to(conn) == "/app/viaxe/customers/#{customer.id}"
    end
  end

  describe "VisaController delete/2" do
    test "removes visa from customer and redirects", %{conn: conn, customer: customer} do
      {:ok, visa} =
        TravelDocuments.create_visa(%{
          customer_id: customer.id,
          country: "US"
        })

      conn =
        delete(conn, "/app/viaxe/customers/#{customer.id}/visas/#{visa.id}")

      assert redirected_to(conn) == "/app/viaxe/customers/#{customer.id}"
    end
  end

  # ── LoyaltyProgramController (nested under customers) ────────────────────────

  describe "LoyaltyProgramController create/2" do
    test "adds loyalty program to customer and redirects", %{conn: conn, customer: customer} do
      params = %{
        "loyalty_program" => %{
          "program_name" => "AAdvantage",
          "program_type" => "airline",
          "member_number" => "AA123456",
          "tier" => "Gold"
        }
      }

      conn = post(conn, "/app/viaxe/customers/#{customer.id}/loyalty_programs", params)
      assert redirected_to(conn) == "/app/viaxe/customers/#{customer.id}"
    end
  end

  describe "LoyaltyProgramController delete/2" do
    test "removes loyalty program from customer and redirects", %{conn: conn, customer: customer} do
      {:ok, program} =
        TravelDocuments.create_loyalty_program(%{
          customer_id: customer.id,
          program_name: "Marriott Bonvoy",
          member_number: "MBV789012"
        })

      conn =
        delete(conn, "/app/viaxe/customers/#{customer.id}/loyalty_programs/#{program.id}")

      assert redirected_to(conn) == "/app/viaxe/customers/#{customer.id}"
    end
  end
end
