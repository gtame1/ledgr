defmodule LedgrWeb.Domains.AumentaMiPension.ConversationListController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.Conversations
  alias Ledgr.Domains.AumentaMiPension.CrmEntries
  alias Ledgr.Domains.AumentaMiPension.CrmEntries.CrmEntry

  # All writeable fields on the CRM overlay — both the CRM pipeline
  # group and the four-axis state group. The form on the show page
  # submits any subset of these on each `change`.
  @crm_fields ~w(
    contact_stage
    sales_stage
    funnel_stage
    qualification_verdict
    escalation_status
    engagement_health
  )

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

    crm_entry =
      CrmEntries.get_by_conversation_id(conversation.id) || %CrmEntry{}

    render(conn, :show,
      conversation: conversation,
      crm_entry: crm_entry,
      # CRM pipeline
      crm_contact_stage_options: CrmEntry.contact_stage_options(),
      crm_sales_stage_options: CrmEntry.sales_stage_options(),
      # Four-axis state
      crm_funnel_stage_options: CrmEntry.funnel_stage_options(),
      crm_qualification_verdict_options: CrmEntry.qualification_verdict_options(),
      crm_escalation_status_options: CrmEntry.escalation_status_options(),
      crm_engagement_health_options: CrmEntry.engagement_health_options(),
      prev_id: prev_id,
      next_id: next_id,
      filter_qs: encode_filter_qs(filter_opts)
    )
  end

  @doc """
  Auto-save endpoint for the CRM card. Each axis select on the show
  page submits the whole form on `change`, so every field is sent
  every time — we just upsert what's there.

  All four axes live on the Ledgr-owned `conversation_crm` overlay
  table; we do NOT write to the bot-owned `conversations.funnel_stage`
  column from here. (The bot redesign will eventually make the
  bot-side state machine match these axes.)

  The hidden `_filters` input round-trips the list-filter query string
  so the redirect lands back in the same filtered context.
  """
  def update_crm(conn, %{"id" => id} = params) do
    filter_qs = redirect_filter_qs(params["_filters"])

    crm_attrs = Map.take(params, @crm_fields)

    case CrmEntries.upsert(id, crm_attrs) do
      {:ok, _entry} ->
        conn
        |> put_flash(:info, "Guardado")
        |> redirect(to: dp(conn, "/conversations/#{id}") <> filter_qs)

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_flash(:error, "Error guardando CRM: #{inspect(cs.errors)}")
        |> redirect(to: dp(conn, "/conversations/#{id}") <> filter_qs)
    end
  end

  # The CRM form ships `_filters` as already-encoded query (without the
  # leading "?"). Re-attach the "?" for the redirect; treat blank as "".
  defp redirect_filter_qs(nil), do: ""
  defp redirect_filter_qs(""), do: ""
  defp redirect_filter_qs(qs) when is_binary(qs), do: "?" <> qs

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
  embed_templates "conversation_list_html/*"

  # Bot-side funnel_stage label map. This is the *bot's* vocabulary
  # (greeting, education, agent_offered, ...) — separate from the
  # operator's four-axis overlay vocabulary, which lives on
  # `Ledgr.Domains.AumentaMiPension.CrmEntries.CrmEntry`.
  @funnel_labels %{
    "greeting" => "Saludo",
    "education" => "Educación",
    "data_collection" => "Recolección de Datos",
    "qualification" => "Calificación",
    "simulation_sent" => "Simulación Enviada",
    "agent_offered" => "Agente Ofrecido",
    "agent_search" => "Búsqueda de Agente",
    "agent_recommended" => "Agente Recomendado",
    "consultation_active" => "Consulta Activa",
    "consultation_complete" => "Consulta Completada",
    "guide_offered" => "Guía Ofrecida",
    "guide_delivered" => "Guía Entregada",
    "guide_paid" => "Guía Pagada",
    "payment_link_sent" => "Link de Pago Enviado",
    "completed" => "Completada"
  }

  @doc """
  Human-readable Spanish label for a **bot** funnel stage. Falls back
  to a title-cased version of the raw value when an unknown stage
  shows up.
  """
  def funnel_stage_label(nil), do: "---"

  def funnel_stage_label(stage) when is_binary(stage) do
    Map.get_lazy(@funnel_labels, stage, fn ->
      stage |> String.replace("_", " ") |> String.capitalize()
    end)
  end

  def funnel_stage_label(stage), do: funnel_stage_label(to_string(stage))
end
