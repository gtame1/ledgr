defmodule LedgrWeb.Domains.Viaxe.LoyaltyProgramController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.Viaxe.TravelDocuments

  def create(conn, %{"customer_id" => customer_id, "loyalty_program" => params}) do
    params = Map.put(params, "customer_id", customer_id)

    case TravelDocuments.create_loyalty_program(params) do
      {:ok, _program} ->
        conn
        |> put_flash(:info, "Loyalty program added.")
        |> redirect(to: dp(conn, "/customers/#{customer_id}"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not add loyalty program. Please check the details.")
        |> redirect(to: dp(conn, "/customers/#{customer_id}"))
    end
  end

  def delete(conn, %{"customer_id" => customer_id, "loyalty_program_id" => program_id}) do
    case TravelDocuments.delete_loyalty_program(program_id) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Loyalty program removed.")
        |> redirect(to: dp(conn, "/customers/#{customer_id}"))

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Loyalty program not found.")
        |> redirect(to: dp(conn, "/customers/#{customer_id}"))
    end
  end
end
