defmodule LedgrWeb.Domains.EscuelaDeDinero.DiagnosticoController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.EscuelaDeDinero.Diagnosticos

  def index(conn, params) do
    filters = filters(params)

    render(conn, :index,
      diagnosticos: Diagnosticos.list(filters),
      filters: filters
    )
  end

  def show(conn, %{"id" => id}) do
    diagnostico = Diagnosticos.get!(id)

    render(conn, :show,
      diagnostico: diagnostico,
      movimientos: Diagnosticos.movimientos(id)
    )
  end

  defp filters(params) do
    %{
      status: params["status"],
      banda: params["banda"],
      colchon: params["colchon"]
    }
  end
end

defmodule LedgrWeb.Domains.EscuelaDeDinero.DiagnosticoHTML do
  use LedgrWeb, :html
  use LedgrWeb.Domains.EscuelaDeDinero.StateLabels
  embed_templates "diagnostico_html/*"
end
