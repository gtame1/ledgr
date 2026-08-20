defmodule LedgrWeb.Domains.Viaxe.RecommendationControllerTest do
  use LedgrWeb.ConnCase

  alias Ledgr.Domains.Viaxe.Recommendations

  setup %{conn: conn} do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)

    {:ok, user} =
      Ledgr.Core.Accounts.create_user(%{email: "viaxe@test.example", password: "password123!"})

    conn = Phoenix.ConnTest.init_test_session(conn, %{"user_id:viaxe" => user.id})

    {:ok, rec} =
      Recommendations.create_recommendation(%{
        name: "El Cardenal",
        city: "Mexico City",
        country: "MX",
        category: "restaurant",
        price_range: "$$",
        rating: 5
      })

    {:ok, conn: conn, rec: rec}
  end

  describe "index/2" do
    test "lists all recommendations", %{conn: conn, rec: rec} do
      conn = get(conn, "/app/viaxe/recommendations")
      assert html_response(conn, 200) =~ rec.name
    end

    test "filters by country", %{conn: conn, rec: rec} do
      conn = get(conn, "/app/viaxe/recommendations?country=MX")
      assert html_response(conn, 200) =~ rec.name
    end

    test "filters by city", %{conn: conn, rec: rec} do
      conn = get(conn, "/app/viaxe/recommendations?city=Mexico+City")
      assert html_response(conn, 200) =~ rec.name
    end

    test "filters by category", %{conn: conn, rec: rec} do
      conn = get(conn, "/app/viaxe/recommendations?category=restaurant")
      assert html_response(conn, 200) =~ rec.name
    end
  end

  # NOTE: The recommendations show template does not exist yet (/recommendations/:id
  # route is defined but no show.html.heex was created). Add a show/2 test here
  # once the template is built.

  describe "new/2" do
    test "renders new form", %{conn: conn} do
      conn = get(conn, "/app/viaxe/recommendations/new")
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "create/2" do
    test "creates recommendation and redirects on valid params", %{conn: conn} do
      params = %{
        "recommendation" => %{
          "name" => "Contramar",
          "city" => "Mexico City",
          "country" => "MX",
          "category" => "restaurant",
          "price_range" => "$$$",
          "rating" => "5"
        }
      }

      conn = post(conn, "/app/viaxe/recommendations", params)
      assert redirected_to(conn) == "/app/viaxe/recommendations"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "successfully"
    end

    test "renders errors on invalid params", %{conn: conn} do
      params = %{
        "recommendation" => %{
          "name" => "",
          "city" => "",
          "country" => "",
          "category" => ""
        }
      }

      conn = post(conn, "/app/viaxe/recommendations", params)
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "edit/2" do
    test "renders edit form", %{conn: conn, rec: rec} do
      conn = get(conn, "/app/viaxe/recommendations/#{rec.id}/edit")
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "update/2" do
    test "updates recommendation and redirects on valid params", %{conn: conn, rec: rec} do
      params = %{
        "recommendation" => %{
          "name" => "El Cardenal Centro",
          "city" => "Mexico City",
          "country" => "MX",
          "category" => "restaurant"
        }
      }

      conn = put(conn, "/app/viaxe/recommendations/#{rec.id}", params)
      assert redirected_to(conn) == "/app/viaxe/recommendations"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "updated"
    end

    test "renders errors on invalid params", %{conn: conn, rec: rec} do
      params = %{
        "recommendation" => %{
          "name" => "",
          "city" => "",
          "country" => "",
          "category" => ""
        }
      }

      conn = put(conn, "/app/viaxe/recommendations/#{rec.id}", params)
      assert html_response(conn, 200) =~ "form"
    end
  end

  describe "delete/2" do
    test "deletes recommendation and redirects", %{conn: conn, rec: rec} do
      conn = delete(conn, "/app/viaxe/recommendations/#{rec.id}")
      assert redirected_to(conn) == "/app/viaxe/recommendations"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "deleted"
    end
  end
end
