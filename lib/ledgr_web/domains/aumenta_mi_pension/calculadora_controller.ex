defmodule LedgrWeb.Domains.AumentaMiPension.CalculadoraController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.CalculadoraSubmissions

  def index(conn, params) do
    leads_only = params["leads_only"] == "1"

    submissions =
      CalculadoraSubmissions.list_submissions(
        leads_only: leads_only,
        search: params["search"]
      )

    total = CalculadoraSubmissions.count()
    leads = CalculadoraSubmissions.count(leads_only: true)

    render(conn, :index,
      submissions: submissions,
      total: total,
      leads: leads,
      leads_only: leads_only,
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id}) do
    submission = CalculadoraSubmissions.get_submission!(id)
    render(conn, :show, submission: submission)
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.CalculadoraHTML do
  use LedgrWeb, :html
  embed_templates "calculadora_html/*"
end
