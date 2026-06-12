defmodule LedgrWeb.Domains.HelloDoctor.ConversationListController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.BotAdmin
  alias Ledgr.Domains.HelloDoctor.ConversationFeedback
  alias Ledgr.Domains.HelloDoctor.Conversations
  alias Ledgr.Domains.HelloDoctor.ConversationFunnelExport

  def index(conn, params) do
    filters = filter_opts(params)

    conversations = Conversations.list_conversations(filters)

    render(conn, :index,
      conversations: conversations,
      current_status: params["status"],
      current_funnel_stage: params["funnel_stage"],
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id} = params) do
    conversation = Conversations.get_conversation!(id)
    filters = filter_opts(params)

    %{prev_id: prev_id, next_id: next_id} = Conversations.neighbors(conversation, filters)

    render(conn, :show,
      conversation: conversation,
      prev_id: prev_id,
      next_id: next_id,
      filter_qs: encode_filter_qs(filters),
      filters: filters,
      feedback_categories: ConversationFeedback.failure_categories(),
      marker: get_session(conn, :triage_marker) || ""
    )
  end

  @doc """
  Quality feedback panel on the conversation detail page. Pushes the mark
  to the bot's admin API (bot ADR-059) — the bot's `conversations` row is
  the single store; nothing is written locally.

  Signal-dependent clearing: marking good clears the bad-only fields
  (category, first-bad anchor, corrected response) and vice versa, so a
  re-verdict never leaves stale structure behind.
  """
  def update_feedback(conn, %{"id" => id} = params) do
    marker = presence(params["marked_by"]) || get_session(conn, :triage_marker)
    signal = params["signal"]

    cond do
      is_nil(marker) ->
        feedback_redirect(conn, id, params, :error, "Set your handle (marked by) first.")

      signal not in ["good", "bad"] ->
        feedback_redirect(conn, id, params, :error, "Pick a verdict: good or bad.")

      signal == "bad" and presence(params["failure_category"]) == nil ->
        feedback_redirect(conn, id, params, :error, "A bad mark needs a failure category.")

      signal == "bad" and presence(params["notes"]) == nil ->
        feedback_redirect(conn, id, params, :error, "A bad mark needs a one-line rationale.")

      true ->
        attrs =
          case signal do
            "good" ->
              %{
                signal: "good",
                exemplary_message_id: params["exemplary_message_id"] || "",
                failure_category: "",
                first_bad_message_id: "",
                corrected_response: ""
              }

            "bad" ->
              %{
                signal: "bad",
                failure_category: params["failure_category"] || "",
                first_bad_message_id: params["first_bad_message_id"] || "",
                corrected_response: params["corrected_response"] || "",
                exemplary_message_id: ""
              }
          end
          |> Map.merge(%{
            corpus_candidate: params["corpus_candidate"] == "true",
            notes: params["notes"] || "",
            marked_by: marker
          })

        {kind, msg} =
          case BotAdmin.mark_conversation(id, attrs) do
            {:ok, _} -> {:info, "Feedback saved (#{signal})."}
            {:error, reason} -> {:error, "Couldn't save feedback: #{reason}"}
          end

        conn
        |> put_session(:triage_marker, marker)
        |> feedback_redirect(id, params, kind, msg)
    end
  end

  @doc """
  Live operator case note (bot ADR-059): the bot injects it into the LLM
  context on every later turn of this conversation. Blank clears it.
  """
  def update_operator_notes(conn, %{"id" => id} = params) do
    marker = presence(params["updated_by"]) || get_session(conn, :triage_marker)

    if is_nil(marker) do
      feedback_redirect(conn, id, params, :error, "Set your handle first.")
    else
      notes = params["operator_notes"] || ""

      {kind, msg} =
        case BotAdmin.set_operator_notes(id, notes, marker) do
          {:ok, _} ->
            if String.trim(notes) == "",
              do: {:info, "Case note cleared — the bot no longer sees it."},
              else: {:info, "Case note saved — the bot sees it on its next turn."}

          {:error, reason} ->
            {:error, "Couldn't save the case note: #{reason}"}
        end

      conn
      |> put_session(:triage_marker, marker)
      |> feedback_redirect(id, params, kind, msg)
    end
  end

  defp feedback_redirect(conn, id, params, kind, msg) do
    conn
    |> put_flash(kind, msg)
    |> redirect(to: dp(conn, "/conversations/#{id}") <> encode_filter_qs(filter_opts(params)))
  end

  defp presence(nil), do: nil

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp filter_opts(params) do
    [
      status: params["status"],
      funnel_stage: params["funnel_stage"],
      search: params["search"]
    ]
  end

  # Active filters as a query-string suffix ("?status=active"); "" when empty,
  # so it's safe to concatenate onto a path.
  defp encode_filter_qs(filter_opts) do
    qs =
      filter_opts
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> URI.encode_query()

    if qs == "", do: "", else: "?" <> qs
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
