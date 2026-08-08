defmodule LedgrWeb.Domains.EscuelaDeDinero.ConversationController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.EscuelaDeDinero.Conversations

  def index(conn, params) do
    filters = filters(params)

    render(conn, :index,
      conversations: Conversations.list(filters),
      filters: filters
    )
  end

  def show(conn, %{"id" => id}) do
    render(conn, :show,
      conversation: Conversations.get!(id),
      messages: Conversations.messages(id),
      policing_by_turn: Conversations.policing_by_turn(id)
    )
  end

  defp filters(params) do
    %{
      status: params["status"],
      initiated_by: params["initiated_by"],
      person_id: params["person_id"]
    }
  end
end

defmodule LedgrWeb.Domains.EscuelaDeDinero.ConversationHTML do
  use LedgrWeb, :html
  use LedgrWeb.Domains.EscuelaDeDinero.StateLabels
  embed_templates "conversation_html/*"
end
