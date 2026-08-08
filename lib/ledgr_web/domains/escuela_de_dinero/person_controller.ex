defmodule LedgrWeb.Domains.EscuelaDeDinero.PersonController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.EscuelaDeDinero.People

  def index(conn, params) do
    filters = filters(params)

    render(conn, :index,
      people: People.list(filters),
      etapas: People.etapas_present(),
      filters: filters
    )
  end

  def show(conn, %{"id" => id}) do
    person = People.get!(id)

    render(conn, :show,
      person: person,
      diagnosticos: People.diagnosticos(id),
      movimientos: People.movimientos(id),
      conversations: People.conversations(id),
      referrals: People.kubo_referrals(id)
    )
  end

  defp filters(params) do
    %{
      etapa: params["etapa"],
      mode: params["mode"],
      baja: params["baja"],
      search: params["search"]
    }
  end
end

defmodule LedgrWeb.Domains.EscuelaDeDinero.PersonHTML do
  use LedgrWeb, :html
  use LedgrWeb.Domains.EscuelaDeDinero.StateLabels
  embed_templates "person_html/*"
end
