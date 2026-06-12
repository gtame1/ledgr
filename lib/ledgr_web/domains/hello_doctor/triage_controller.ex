defmodule LedgrWeb.Domains.HelloDoctor.TriageController do
  use LedgrWeb, :controller

  import Ecto.Query, warn: false

  alias Ledgr.Domains.HelloDoctor.BotAdmin
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
  alias Ledgr.Domains.HelloDoctor.Conversations.Conversation
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.Patients.Patient

  @auto_hints ~w[unmarked likely_bad looks_good safety_review regression abandoned review neutral good bad]

  # Inbox ordering: most actionable first. Recency is preserved within a
  # bucket (Enum.sort_by is stable; the bot returns recent-first).
  @hint_priority %{
    "safety_review" => 0,
    "likely_bad" => 1,
    "regression" => 2,
    "review" => 3,
    "abandoned" => 4,
    "neutral" => 5,
    "looks_good" => 6
  }

  def index(conn, params) do
    signal = blank_to_nil(params["signal"]) || "unmarked"
    tenant = blank_to_nil(params["tenant"])
    corpus_only = params["corpus_only"] == "true"
    marker = blank_to_nil(params["marker"]) || get_session(conn, :triage_marker) || ""

    opts =
      [signal: signal, tenant: tenant, limit: params["limit"] || "50"]
      |> Keyword.merge(if corpus_only, do: [corpus_candidate: "true"], else: [])

    {conversations, error} =
      case BotAdmin.list_conversations(opts) do
        {:ok, list} when is_list(list) -> {enrich_with_local(list), nil}
        {:ok, %{"conversations" => list}} when is_list(list) -> {enrich_with_local(list), nil}
        {:ok, other} -> {[], "Unexpected response shape: #{inspect(other, limit: 100)}"}
        {:error, reason} -> {[], reason}
      end

    conversations = sort_by_hint_priority(conversations)

    conn
    |> put_session(:triage_marker, marker)
    |> render(:index,
      conversations: conversations,
      hint_counts: Enum.frequencies_by(conversations, &Map.get(&1, "auto_hint")),
      signal: signal,
      tenant: tenant,
      corpus_only: corpus_only,
      marker: marker,
      error: error,
      auto_hints: @auto_hints
    )
  end

  defp sort_by_hint_priority(conversations) do
    Enum.sort_by(conversations, fn conv ->
      Map.get(@hint_priority, Map.get(conv, "auto_hint"), 5)
    end)
  end

  # The bot's /admin/conversations response only carries identifiers + funnel
  # metadata — no patient or doctor info. We cross-reference each id against
  # our local conversations table (which the bot writes to the same DB) to
  # surface patient name / phone and the most recent doctor for the row.
  #
  # If the local row is missing (rare — conversation hasn't synced yet) we
  # leave the enrichment fields nil and the template renders "—".
  defp enrich_with_local(conversations) do
    ids = conversations |> Enum.map(&Map.get(&1, "id")) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      conversations
    else
      # Latest consultation per conversation — to find the assigned doctor.
      latest_consult =
        from cs in Consultation,
          distinct: cs.conversation_id,
          order_by: [asc: cs.conversation_id, desc: cs.assigned_at],
          where: cs.conversation_id in ^ids,
          select: %{conversation_id: cs.conversation_id, doctor_id: cs.doctor_id}

      local =
        from(c in Conversation,
          left_join: p in Patient,
          on: p.id == c.patient_id,
          left_join: lc in subquery(latest_consult),
          on: lc.conversation_id == c.id,
          left_join: d in Doctor,
          on: d.id == lc.doctor_id,
          where: c.id in ^ids,
          select: %{
            id: c.id,
            patient_name: coalesce(p.full_name, p.display_name),
            patient_phone: p.phone,
            doctor_name: d.name
          }
        )
        |> Ledgr.Repo.all()
        |> Map.new(fn row -> {row.id, row} end)

      Enum.map(conversations, fn conv ->
        info = Map.get(local, Map.get(conv, "id"), %{})

        conv
        |> Map.put("patient_name", info[:patient_name])
        |> Map.put("patient_phone", info[:patient_phone])
        |> Map.put("doctor_name", info[:doctor_name])
      end)
    end
  end

  # Marking moved to the conversation detail page (ConversationListController
  # .update_feedback) — Triage is now a read-only review inbox.

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
end

defmodule LedgrWeb.Domains.HelloDoctor.TriageHTML do
  use LedgrWeb, :html
  embed_templates "triage_html/*"

  @doc """
  Builds a query string for the triage page with overrides.
  """
  def triage_query(assigns, overrides) do
    base = %{
      "signal" => assigns.signal,
      "tenant" => assigns.tenant,
      "corpus_only" => if(assigns.corpus_only, do: "true", else: nil),
      "marker" => assigns.marker
    }

    base
    |> Map.merge(Map.new(overrides, fn {k, v} -> {to_string(k), v} end))
    |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
    |> URI.encode_query()
  end

  @doc """
  Renders the auto_hint badge with a color suggestive of severity.
  """
  def hint_badge(nil), do: ""

  def hint_badge(hint) do
    {bg, fg} =
      case hint do
        "likely_bad" -> {"#fee2e2", "#991b1b"}
        "safety_review" -> {"#fef3c7", "#92400e"}
        "regression" -> {"#fee2e2", "#991b1b"}
        "abandoned" -> {"#f3f4f6", "#6b7280"}
        "review" -> {"#fef3c7", "#92400e"}
        "looks_good" -> {"#d1fae5", "#065f46"}
        "neutral" -> {"#f3f4f6", "#6b7280"}
        _ -> {"#f3f4f6", "#6b7280"}
      end

    Phoenix.HTML.raw(
      ~s|<span style="background: #{bg}; color: #{fg}; padding: 0.1rem 0.45rem; border-radius: 0.25rem; font-size: 0.7rem; font-weight: 600;">#{Phoenix.HTML.html_escape(hint) |> Phoenix.HTML.safe_to_string()}</span>|
    )
  end

  @doc """
  Renders the signal badge (good / bad / unmarked).
  """
  def signal_badge(nil), do: hint_badge("unmarked")

  def signal_badge("good") do
    Phoenix.HTML.raw(
      ~s|<span style="background: #d1fae5; color: #065f46; padding: 0.1rem 0.45rem; border-radius: 0.25rem; font-size: 0.7rem; font-weight: 600;">✓ good</span>|
    )
  end

  def signal_badge("bad") do
    Phoenix.HTML.raw(
      ~s|<span style="background: #fee2e2; color: #991b1b; padding: 0.1rem 0.45rem; border-radius: 0.25rem; font-size: 0.7rem; font-weight: 600;">✗ bad</span>|
    )
  end

  def signal_badge(other), do: hint_badge(to_string(other))

  @doc """
  Pulls a display field from the bot's JSON response, tolerating both
  string and atom keys.
  """
  def get_field(map, key, default \\ "—") do
    val =
      cond do
        is_map(map) -> Map.get(map, to_string(key)) || Map.get(map, key)
        true -> nil
      end

    case val do
      nil -> default
      "" -> default
      v -> v
    end
  end

  @doc """
  Renders an ISO-8601 timestamp from the bot as a compact relative time
  ("3m ago", "2h ago", "5d ago"). Returns "—" when nil or unparseable.
  """
  def relative_time(nil), do: "—"
  def relative_time(""), do: "—"

  def relative_time(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> format_relative(DateTime.diff(DateTime.utc_now(), dt, :second))
      _ -> iso
    end
  end

  def relative_time(_), do: "—"

  defp format_relative(secs) when secs < 60, do: "#{secs}s ago"
  defp format_relative(secs) when secs < 3600, do: "#{div(secs, 60)}m ago"
  defp format_relative(secs) when secs < 86_400, do: "#{div(secs, 3600)}h ago"
  defp format_relative(secs), do: "#{div(secs, 86_400)}d ago"
end
