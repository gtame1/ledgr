defmodule LedgrWeb.Domains.HelloDoctor.ConsultationController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.Consultations

  def index(conn, params) do
    filters = %{
      status: params["status"],
      search: params["search"]
    }

    consultations = Consultations.list_consultations(filters)

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

    case Consultations.update_consultation(consultation, %{status: status}) do
      {:ok, consultation} ->
        conn
        |> put_flash(:info, "Status updated to #{status}.")
        |> redirect(to: dp(conn, "/consultations/#{consultation.id}"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to update status.")
        |> redirect(to: dp(conn, "/consultations/#{id}"))
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.ConsultationHTML do
  use LedgrWeb, :html
  embed_templates "consultation_html/*"
end
