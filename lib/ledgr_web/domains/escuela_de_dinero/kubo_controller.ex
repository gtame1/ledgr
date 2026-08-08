defmodule LedgrWeb.Domains.EscuelaDeDinero.KuboController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.EscuelaDeDinero.Calidad

  def index(conn, _params) do
    render(conn, :index,
      referrals: Calidad.list_referrals(),
      gate_summary: Calidad.gate_summary(),
      sin_declaracion: Calidad.referrals_sin_declaracion()
    )
  end
end

defmodule LedgrWeb.Domains.EscuelaDeDinero.KuboHTML do
  use LedgrWeb, :html
  use LedgrWeb.Domains.EscuelaDeDinero.StateLabels
  embed_templates "kubo_html/*"
end
