defmodule LedgrWeb.Domains.HelloDoctor.PaymentController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.Consultations

  def index(conn, params) do
    filters = %{
      payment_status: params["payment_status"]
    }

    consultations = Consultations.list_consultations(filters)
    stats = Consultations.payment_stats()

    render(conn, :index,
      consultations: consultations,
      stats: stats,
      current_payment_status: params["payment_status"]
    )
  end

  def show(conn, %{"id" => id}) do
    consultation = Consultations.get_consultation!(id)

    render(conn, :show, consultation: consultation)
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.PaymentHTML do
  use LedgrWeb, :html
  embed_templates "payment_html/*"
end
