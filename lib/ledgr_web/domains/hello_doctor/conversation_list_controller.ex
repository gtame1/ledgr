defmodule LedgrWeb.Domains.HelloDoctor.ConversationListController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.Conversations
  alias Ledgr.Domains.HelloDoctor.ConversationFunnelExport

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

  @doc """
  Streams the conversation funnel summary as a CSV download. Filter params
  match the index page so whatever's on screen is what downloads.
  """
  def download(conn, params) do
    try do
      csv =
        ConversationFunnelExport.to_csv(
          status: params["status"],
          funnel_stage: params["funnel_stage"],
          search: params["search"],
          limit: params["limit"]
        )

      today = Ledgr.Domains.HelloDoctor.today()
      filename = "hello-doctor-conversation-funnel-#{today}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, csv)
    rescue
      e in Postgrex.Error ->
        # Bot-owned tables / columns may drift faster than our schemas. Surface
        # a short reason inline; full message goes to the logs (it includes the
        # whole SQL query which would blow the session cookie limit).
        require Logger

        Logger.error(
          "[HelloDoctor] Conversation funnel export failed: #{Exception.message(e)}"
        )

        short =
          case e.postgres do
            %{message: msg} -> msg
            _ -> "database error"
          end
          |> to_string()
          |> String.slice(0, 200)

        conn
        |> put_flash(:error, "Couldn't generate the funnel CSV: #{short}")
        |> redirect(to: dp(conn, "/conversations"))
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.ConversationListHTML do
  use LedgrWeb, :html
  embed_templates "conversation_list_html/*"
end
