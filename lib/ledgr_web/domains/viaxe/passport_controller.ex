defmodule LedgrWeb.Domains.Viaxe.PassportController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.Viaxe.TravelDocuments

  def create(conn, %{"customer_id" => customer_id, "passport" => passport_params}) do
    params = Map.put(passport_params, "customer_id", customer_id)

    case TravelDocuments.create_passport(params) do
      {:ok, _passport} ->
        conn
        |> put_flash(:info, "Passport added.")
        |> redirect(to: dp(conn, "/customers/#{customer_id}"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not add passport. Please check the details.")
        |> redirect(to: dp(conn, "/customers/#{customer_id}"))
    end
  end

  def delete(conn, %{"customer_id" => customer_id, "passport_id" => passport_id}) do
    case TravelDocuments.delete_passport(passport_id) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Passport removed.")
        |> redirect(to: dp(conn, "/customers/#{customer_id}"))

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Passport not found.")
        |> redirect(to: dp(conn, "/customers/#{customer_id}"))
    end
  end
end
