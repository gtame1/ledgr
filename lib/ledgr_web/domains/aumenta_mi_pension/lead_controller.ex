defmodule LedgrWeb.Domains.AumentaMiPension.LeadController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.{
    CrmEntries,
    CrmEntries.CrmEntry,
    Leads
  }

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
    leads = Leads.list_leads(filter_opts)

    # Group leads by their effective funnel_stage for sectioned display.
    # The "Sin definir" bucket catches anything that falls outside the
    # five canonical stages (shouldn't happen given the :default
    # fallback in Leads.effective_funnel_stage/1, but safe-guarded).
    grouped =
      Enum.group_by(leads, fn lead ->
        {stage, _source} = Leads.effective_funnel_stage(lead)
        stage
      end)

    stage_order = CrmEntry.funnel_stage_codes() ++ [nil]

    render(conn, :index,
      grouped_leads: grouped,
      stage_order: stage_order,
      current_funnel_stage: params["funnel_stage"],
      current_source: params["source"],
      current_search: params["search"],
      funnel_stage_options: CrmEntry.funnel_stage_options(),
      filter_qs: encode_filter_qs(filter_opts)
    )
  end

  def show(conn, %{"phone" => phone} = params) do
    case Leads.get_lead_by_phone(phone) do
      nil ->
        conn
        |> put_flash(:error, "Lead no encontrado")
        |> redirect(to: dp(conn, "/leads") <> encode_filter_qs(filter_opts(params)))

      lead ->
        {effective_stage, stage_source} = Leads.effective_funnel_stage(lead)
        opts = filter_opts(params)
        %{prev_phone: prev_phone, next_phone: next_phone} = Leads.neighbors(lead, opts)

        render(conn, :show,
          lead: lead,
          effective_funnel_stage: effective_stage,
          funnel_stage_source: stage_source,
          prev_phone: prev_phone,
          next_phone: next_phone,
          # CRM overlay options (shared with the form selects)
          crm_contact_stage_options: CrmEntry.contact_stage_options(),
          crm_sales_stage_options: CrmEntry.sales_stage_options(),
          crm_funnel_stage_options: CrmEntry.funnel_stage_options(),
          crm_qualification_verdict_options: CrmEntry.qualification_verdict_options(),
          crm_escalation_status_options: CrmEntry.escalation_status_options(),
          crm_engagement_health_options: CrmEntry.engagement_health_options(),
          filter_qs: encode_filter_qs(opts)
        )
    end
  end

  @doc """
  Auto-save endpoint for the CRM card on the lead detail page. Same
  contract as the (deleted) per-conversation `update_crm`: each select
  submits the whole form on `change`; we upsert what's there. Phone
  comes from the URL.
  """
  def update_crm(conn, %{"phone" => phone} = params) do
    filter_qs = redirect_filter_qs(params["_filters"])
    crm_attrs = Map.take(params, @crm_fields)

    case CrmEntries.upsert(phone, crm_attrs) do
      {:ok, _entry} ->
        conn
        |> put_flash(:info, "Guardado")
        |> redirect(to: dp(conn, "/leads/#{phone}") <> filter_qs)

      {:error, :invalid_phone} ->
        conn
        |> put_flash(:error, "Teléfono inválido")
        |> redirect(to: dp(conn, "/leads") <> filter_qs)

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_flash(:error, "Error guardando CRM: #{inspect(cs.errors)}")
        |> redirect(to: dp(conn, "/leads/#{phone}") <> filter_qs)
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp filter_opts(params) do
    [
      funnel_stage: params["funnel_stage"],
      source: source_filter(params["source"]),
      search: params["search"]
    ]
  end

  defp source_filter(nil), do: nil
  defp source_filter(""), do: nil

  defp source_filter(value) when is_binary(value) do
    case value do
      "conversation" -> [:conversation]
      "checkup" -> [:checkup]
      "calculadora" -> [:calculadora]
      _ -> nil
    end
  end

  defp source_filter(_), do: nil

  defp redirect_filter_qs(nil), do: ""
  defp redirect_filter_qs(""), do: ""
  defp redirect_filter_qs(qs) when is_binary(qs), do: "?" <> qs

  defp encode_filter_qs(filter_opts) do
    qs =
      filter_opts
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Enum.map(fn
        {k, v} when is_list(v) -> {to_string(k), Enum.join(v, ",")}
        {k, v} -> {to_string(k), to_string(v)}
      end)
      |> URI.encode_query()

    if qs == "", do: "", else: "?" <> qs
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.LeadHTML do
  use LedgrWeb, :html
  use LedgrWeb.Domains.AumentaMiPension.StateLabels
  embed_templates "lead_html/*"

  alias Ledgr.Domains.AumentaMiPension.Leads
  alias Ledgr.Domains.AumentaMiPension.CrmEntries.CrmEntry

  @doc """
  Pretty-print a normalized 10-digit phone for display.
  E.g. `5512345678` → `55 1234 5678`.
  """
  def format_phone(nil), do: "—"

  def format_phone(phone) when is_binary(phone) and byte_size(phone) == 10 do
    <<a::binary-2, b::binary-4, c::binary-4>> = phone
    "#{a} #{b} #{c}"
  end

  def format_phone(phone), do: phone

  @doc """
  Spanish label for a stage-grouping section header.
  Falls back to CrmEntry's funnel_stage_label/1 for known new-vocab values.
  """
  def section_label(nil), do: "Sin definir"

  def section_label(stage) when is_binary(stage) do
    CrmEntry.funnel_stage_label(stage) || stage
  end

  @doc "Spanish label for a source atom badge."
  def source_label(:conversation), do: "Conv"
  def source_label(:checkup), do: "Checkup"
  def source_label(:calculadora), do: "Calc"
  def source_label(other), do: to_string(other)

  @doc """
  Returns `{label, color_class}` for the funnel_stage-source badge on
  the lead detail page. Used to show whether the displayed value came
  from operator override, bot derivation, or default fallback.
  """
  def funnel_source_badge(:operator), do: {"Operador", "background: #fef3c7; color: #92400e;"}
  def funnel_source_badge(:bot), do: {"Bot (última conv.)", "background: #dbe5f5; color: #1f3b6a;"}
  def funnel_source_badge(:default), do: {"Por defecto", "background: #e5e7eb; color: #374151;"}
end
