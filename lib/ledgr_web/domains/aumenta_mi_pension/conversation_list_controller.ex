defmodule LedgrWeb.Domains.AumentaMiPension.ConversationListController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.Conversations
  alias Ledgr.Domains.AumentaMiPension.ConversationBuckets
  alias Ledgr.Domains.AumentaMiPension.ConversationBuckets.ConversationBucket
  alias Ledgr.Domains.AumentaMiPension.Phones

  @bucket_fields Enum.map(ConversationBucket.bucket_fields(), &Atom.to_string/1)

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
      bucket: ConversationBuckets.get(id),
      bucket_options: ConversationBucket.buckets(),
      prev_id: prev_id,
      next_id: next_id,
      filter_qs: encode_filter_qs(filter_opts)
    )
  end

  @doc """
  Save endpoint for the conversation overlay (buckets + case notes) on
  the detail page. Both the checkbox card and the case-notes card POST
  here; each submits its own subset of fields, and `upsert/2` loads the
  existing row first so a partial submit leaves the other fields intact.
  The checkbox card submits all six flags on every change (each checkbox
  backed by a hidden `false` input). Conversation id comes from the URL.
  """
  def update_buckets(conn, %{"id" => id} = params) do
    filter_qs = redirect_filter_qs(params["_filters"])
    attrs = Map.take(params, ["case_notes" | @bucket_fields])

    case ConversationBuckets.upsert(id, attrs) do
      {:ok, _bucket} ->
        conn
        |> put_flash(:info, "Guardado")
        |> redirect(to: dp(conn, "/conversations/#{id}") <> filter_qs)

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_flash(:error, "Error guardando: #{inspect(cs.errors)}")
        |> redirect(to: dp(conn, "/conversations/#{id}") <> filter_qs)
    end
  end

  defp filter_opts(params) do
    [
      status: params["status"],
      funnel_stage: params["funnel_stage"],
      search: params["search"]
    ]
  end

  # Rebuilds the "?..." suffix from the hidden `_filters` field the
  # buckets form round-trips, so the post-save redirect preserves the
  # list filters the operator had active.
  defp redirect_filter_qs(nil), do: ""
  defp redirect_filter_qs(""), do: ""
  defp redirect_filter_qs(qs) when is_binary(qs), do: "?" <> qs

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
