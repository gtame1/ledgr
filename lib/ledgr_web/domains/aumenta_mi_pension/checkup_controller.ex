defmodule LedgrWeb.Domains.AumentaMiPension.CheckupController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.CheckupResponses

  def index(conn, params) do
    leads_only = params["leads_only"] == "1"

    responses =
      CheckupResponses.list_responses(
        leads_only: leads_only,
        search: params["search"]
      )

    total = CheckupResponses.count()
    leads = CheckupResponses.count(leads_only: true)

    render(conn, :index,
      responses: responses,
      total: total,
      leads: leads,
      leads_only: leads_only,
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id}) do
    response = CheckupResponses.get_response!(id)
    render(conn, :show, response: response)
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
