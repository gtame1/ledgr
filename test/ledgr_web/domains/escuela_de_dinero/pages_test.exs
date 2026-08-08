defmodule LedgrWeb.Domains.EscuelaDeDinero.PagesTest do
  @moduledoc """
  Every page renders against an **empty** database.

  That is the case worth pinning. This domain reads a database it does not own,
  so it will meet missing rows, missing JSONB keys and zero denominators in
  production long before it meets a full one — and those are exactly where
  `Float.round(nil)` and division-by-zero live. A page that survives no data
  survives a bot-side shape change.
  """
  use LedgrWeb.ConnCase

  @prefix "/app/escuela-de-dinero"

  setup %{conn: conn} do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.EscuelaDeDinero)

    {:ok, user} =
      Ledgr.Core.Accounts.create_user(%{
        email: "socio@escueladinero.test",
        password: "password123!"
      })

    conn = Phoenix.ConnTest.init_test_session(conn, %{"user_id:escuela-de-dinero" => user.id})

    {:ok, conn: conn}
  end

  describe "with an empty database" do
    for {label, path} <- [
          {"Panel", ""},
          {"Personas", "/personas"},
          {"Diagnósticos", "/diagnosticos"},
          {"Movimientos", "/movimientos"},
          {"Conversaciones", "/conversaciones"},
          {"Calidad", "/calidad"},
          {"Kubo", "/kubo"}
        ] do
      test "#{label} renders", %{conn: conn} do
        conn = get(conn, @prefix <> unquote(path))
        assert html_response(conn, 200) =~ unquote(label)
      end
    end

    test "the Panel reports 0% rather than dividing by zero", %{conn: conn} do
      html = conn |> get(@prefix) |> html_response(200)

      assert html =~ "Tasa de completado"
      assert html =~ "0%"
    end

    test "the Panel date window is anchored to Mexico City, not UTC", %{conn: conn} do
      # A UTC-anchored window renders tomorrow's date for most of the evening in
      # Mexico. Assert the window ends today, local.
      html = conn |> get(@prefix) |> html_response(200)
      today = Ledgr.Domains.EscuelaDeDinero.today()

      assert html =~ Calendar.strftime(today, "%d/%m/%Y")
    end
  end

  describe "auth" do
    test "an unauthenticated request is redirected to login", %{conn: _conn} do
      conn = get(Phoenix.ConnTest.build_conn(), @prefix <> "/personas")
      assert redirected_to(conn) == @prefix <> "/login"
    end

    test "a session for another domain does not grant access" do
      Ledgr.Repo.put_active_repo(Ledgr.Repos.EscuelaDeDinero)

      {:ok, user} =
        Ledgr.Core.Accounts.create_user(%{
          email: "otro@escueladinero.test",
          password: "password123!"
        })

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{"user_id:aumenta-mi-pension" => user.id})
        |> get(@prefix <> "/personas")

      assert redirected_to(conn) == @prefix <> "/login"
    end
  end
end
