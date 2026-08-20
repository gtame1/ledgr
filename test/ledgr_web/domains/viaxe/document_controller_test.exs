defmodule LedgrWeb.Domains.Viaxe.DocumentControllerTest do
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

  describe "index/2" do
    test "renders document overview page", %{conn: conn} do
      conn = get(conn, "/app/viaxe/documents")
      assert html_response(conn, 200)
    end

    test "shows passports when present", %{conn: conn, customer: customer} do
      {:ok, _passport} =
        TravelDocuments.create_passport(%{
          customer_id: customer.id,
          country: "MX",
          number: "G01234567",
          expiry_date: ~D[2030-06-01]
        })

      conn = get(conn, "/app/viaxe/documents")
      assert html_response(conn, 200) =~ "G01234567"
    end

    test "shows visas when present", %{conn: conn, customer: customer} do
      {:ok, _visa} =
        TravelDocuments.create_visa(%{
          customer_id: customer.id,
          country: "US",
          visa_type: "tourist"
        })

      conn = get(conn, "/app/viaxe/documents")
      # Page should render successfully with visa data
      assert html_response(conn, 200) =~ "US"
    end

    test "shows loyalty programs when present", %{conn: conn, customer: customer} do
      {:ok, _program} =
        TravelDocuments.create_loyalty_program(%{
          customer_id: customer.id,
          program_name: "AAdvantage",
          member_number: "AA123456"
        })

      conn = get(conn, "/app/viaxe/documents")
      assert html_response(conn, 200) =~ "AAdvantage"
    end
  end
end
