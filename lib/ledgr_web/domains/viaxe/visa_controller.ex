defmodule LedgrWeb.Domains.Viaxe.VisaController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.Viaxe.TravelDocuments

  def create(conn, %{"customer_id" => customer_id, "visa" => visa_params}) do
    params = Map.put(visa_params, "customer_id", customer_id)

    case TravelDocuments.create_visa(params) do
      {:ok, _visa} ->
        conn
        |> put_flash(:info, "Visa added.")
        |> redirect(to: dp(conn, "/customers/#{customer_id}"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not add visa. Please check the details.")
        |> redirect(to: dp(conn, "/customers/#{customer_id}"))
    end
  end

  def delete(conn, %{"customer_id" => customer_id, "visa_id" => visa_id}) do
    case TravelDocuments.delete_visa(visa_id) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Visa removed.")
        |> redirect(to: dp(conn, "/customers/#{customer_id}"))

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Visa not found.")
        |> redirect(to: dp(conn, "/customers/#{customer_id}"))
    end
  end
end
