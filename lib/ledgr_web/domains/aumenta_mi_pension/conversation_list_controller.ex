defmodule LedgrWeb.Domains.AumentaMiPension.ConversationListController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.Conversations
  alias Ledgr.Domains.AumentaMiPension.Phones

  def index(conn, params) do
    filter_opts = filter_opts(params)

    conversations = Conversations.list_conversations(filter_opts)

    render(conn, :index,
      conversations: conversations,
      current_status: params["status"],
      current_funnel_stage: params["funnel_stage"],
      current_search: params["search"],
      funnel_stages: Conversations.funnel_stages(),
      filter_qs: encode_filter_qs(filter_opts)
    )
  end

  def show(conn, %{"id" => id} = params) do
    conversation = Conversations.get_conversation!(id)
    filter_opts = filter_opts(params)

    %{prev_id: prev_id, next_id: next_id} =
      Conversations.neighbors(conversation, filter_opts)

    # CRM annotations now live at the lead level (see Leads context).
    # Expose the normalized phone so the show template can link to
    # the lead detail page if we know who this conversation belongs to.
    lead_phone =
      if conversation.customer && conversation.customer.phone do
        Phones.normalize(conversation.customer.phone)
      end

    render(conn, :show,
      conversation: conversation,
      lead_phone: lead_phone,
      prev_id: prev_id,
      next_id: next_id,
      filter_qs: encode_filter_qs(filter_opts)
    )
  end

  defp filter_opts(params) do
    [
      status: params["status"],
      funnel_stage: params["funnel_stage"],
      search: params["search"]
    ]
  end

  # Encodes the active filters as a query-string suffix (e.g. "?status=active").
  # Returns "" when no filters are set, so callers can safely concatenate.
  defp encode_filter_qs(filter_opts) do
    qs =
      filter_opts
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> URI.encode_query()

    if qs == "", do: "", else: "?" <> qs
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.ConversationListHTML do
  use LedgrWeb, :html
  use LedgrWeb.Domains.AumentaMiPension.StateLabels
  embed_templates "conversation_list_html/*"
end
