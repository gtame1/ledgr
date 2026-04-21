defmodule LedgrWeb.Domains.AumentaMiPension.AgentChatController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.AgentAssistantMessages

  def index(conn, params) do
    threads = AgentAssistantMessages.list_by_agent(search: params["search"])

    render(conn, :index,
      threads: threads,
      current_search: params["search"] || ""
    )
  end

  def show(conn, %{"id" => agent_id} = params) do
    {agent, messages} = AgentAssistantMessages.get_agent_thread!(agent_id)

    grouped =
      messages
      |> Enum.group_by(& &1.consultation_id)
      |> Enum.sort_by(fn {_k, msgs} -> List.first(msgs).created_at end)

    render(conn, :show,
      agent: agent,
      grouped_messages: grouped,
      current_filter: params["consultation_id"]
    )
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.AgentChatHTML do
  use LedgrWeb, :html
  embed_templates "agent_chat_html/*"
end
