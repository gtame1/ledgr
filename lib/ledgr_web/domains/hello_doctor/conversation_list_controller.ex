defmodule LedgrWeb.Domains.HelloDoctor.ConversationListController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.Conversations

  def index(conn, params) do
    filters = %{
      status: params["status"],
      funnel_stage: params["funnel_stage"],
      search: params["search"]
    }

    conversations = Conversations.list_conversations(filters)

    render(conn, :index,
      conversations: conversations,
      current_status: params["status"],
      current_funnel_stage: params["funnel_stage"],
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id}) do
    conversation = Conversations.get_conversation!(id)

    render(conn, :show, conversation: conversation)
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.ConversationListHTML do
  use LedgrWeb, :html
  embed_templates "conversation_list_html/*"
end
