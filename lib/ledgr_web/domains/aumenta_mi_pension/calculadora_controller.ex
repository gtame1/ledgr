defmodule LedgrWeb.Domains.AumentaMiPension.CalculadoraController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.CalculadoraSubmissions

  def index(conn, params) do
    opts = filter_opts(params)

    submissions = CalculadoraSubmissions.list_submissions(opts)

    total = CalculadoraSubmissions.count()
    leads = CalculadoraSubmissions.count(leads_only: true)

    render(conn, :index,
      submissions: submissions,
      total: total,
      leads: leads,
      leads_only: opts[:leads_only],
      current_search: params["search"],
      filter_qs: encode_filter_qs(opts)
    )
  end

  def show(conn, %{"id" => id} = params) do
    submission = CalculadoraSubmissions.get_submission!(id)
    opts = filter_opts(params)
    %{prev_id: prev_id, next_id: next_id} = CalculadoraSubmissions.neighbors(submission, opts)

    render(conn, :show,
      submission: submission,
      prev_id: prev_id,
      next_id: next_id,
      filter_qs: encode_filter_qs(opts)
    )
  end

  defp filter_opts(params) do
    [
      leads_only: params["leads_only"] == "1",
      search: params["search"]
    ]
  end

  # Encodes active filters as a query-string suffix ("?leads_only=1&search=...").
  # Returns "" when nothing is set. `leads_only` only appears when true.
  defp encode_filter_qs(opts) do
    qs =
      opts
      |> Enum.flat_map(fn
        {:leads_only, true} -> [{"leads_only", "1"}]
        {:leads_only, _} -> []
        {_k, v} when v in [nil, ""] -> []
        {k, v} -> [{to_string(k), v}]
      end)
      |> URI.encode_query()

    if qs == "", do: "", else: "?" <> qs
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.CalculadoraHTML do
  use LedgrWeb, :html
  embed_templates "calculadora_html/*"
end
