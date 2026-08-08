defmodule LedgrWeb.Domains.EscuelaDeDinero.MovimientoController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.EscuelaDeDinero.Movimientos

  def index(conn, params) do
    filters = filters(params)

    render(conn, :index,
      movimientos: Movimientos.list(filters),
      areas: Movimientos.areas_present(),
      filters: filters
    )
  end

  defp filters(params) do
    %{
      estado: params["estado"],
      area: params["area"],
      vencidos: params["vencidos"],
      agotados: params["agotados"]
    }
  end
end

defmodule LedgrWeb.Domains.EscuelaDeDinero.MovimientoHTML do
  use LedgrWeb, :html
  use LedgrWeb.Domains.EscuelaDeDinero.StateLabels
  embed_templates "movimiento_html/*"
end
