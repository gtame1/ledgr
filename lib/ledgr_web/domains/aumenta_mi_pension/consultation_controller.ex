defmodule LedgrWeb.Domains.AumentaMiPension.ConsultationController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.Consultations

  def index(conn, params) do
    consultations =
      Consultations.list_consultations(
        status: params["status"],
        search: params["search"]
      )

    render(conn, :index,
      consultations: consultations,
      current_status: params["status"],
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id}) do
    consultation = Consultations.get_consultation!(id)

    render(conn, :show, consultation: consultation)
  end

  def update_status(conn, %{"id" => id, "status" => status}) do
    consultation = Consultations.get_consultation!(id)

    case Consultations.update_status(consultation, status) do
      {:ok, consultation} ->
        conn
        |> put_flash(:info, "Estatus actualizado a #{status}.")
        |> redirect(to: dp(conn, "/consultations/#{consultation.id}"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "No se pudo actualizar el estatus.")
        |> redirect(to: dp(conn, "/consultations/#{id}"))
    end
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.ConsultationHTML do
  use LedgrWeb, :html
  embed_templates "consultation_html/*"
end
