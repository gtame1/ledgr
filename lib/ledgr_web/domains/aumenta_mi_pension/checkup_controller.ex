defmodule LedgrWeb.Domains.AumentaMiPension.CheckupController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.CheckupResponses

  def index(conn, params) do
    opts = filter_opts(params)

    responses = CheckupResponses.list_responses(opts)

    total = CheckupResponses.count()
    leads = CheckupResponses.count(leads_only: true)

    render(conn, :index,
      responses: responses,
      total: total,
      leads: leads,
      leads_only: opts[:leads_only],
      current_search: params["search"],
      filter_qs: encode_filter_qs(opts)
    )
  end

  def show(conn, %{"id" => id} = params) do
    response = CheckupResponses.get_response!(id)
    opts = filter_opts(params)
    %{prev_id: prev_id, next_id: next_id} = CheckupResponses.neighbors(response, opts)

    render(conn, :show,
      response: response,
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

defmodule LedgrWeb.Domains.AumentaMiPension.CheckupHTML do
  use LedgrWeb, :html
  embed_templates "checkup_html/*"

  def bool_label(true), do: "Sí"
  def bool_label(false), do: "No"
  def bool_label(_), do: "---"

  @doc "Last wizard step the user reached (e.g. 'm6_summary'). nil if not present."
  def current_mission(%{"_currentMission" => step}) when is_binary(step) and step != "", do: step
  def current_mission(_), do: nil

  @doc "When the user first opened the wizard (ISO 8601 string from the bot)."
  def first_seen_at(%{"_firstSeenAt" => ts}) when is_binary(ts) and ts != "" do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> fmt_datetime(dt)
      _ -> ts
    end
  end

  def first_seen_at(_), do: nil
end
