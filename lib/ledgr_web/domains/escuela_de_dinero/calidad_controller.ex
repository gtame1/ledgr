defmodule LedgrWeb.Domains.EscuelaDeDinero.CalidadController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.EscuelaDeDinero.Calidad

  def index(conn, params) do
    filters = %{severity: params["severity"], event_type: params["event_type"]}

    render(conn, :index,
      events: Calidad.list_events(filters),
      rule_summary: Calidad.rule_summary(),
      severity_totals: Calidad.severity_totals(),
      sin_declaracion: Calidad.referrals_sin_declaracion(),
      filters: filters
    )
  end
end

defmodule LedgrWeb.Domains.EscuelaDeDinero.CalidadHTML do
  use LedgrWeb, :html
  use LedgrWeb.Domains.EscuelaDeDinero.StateLabels
  embed_templates "calidad_html/*"
end
