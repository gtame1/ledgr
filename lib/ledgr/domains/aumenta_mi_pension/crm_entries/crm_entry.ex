defmodule Ledgr.Domains.AumentaMiPension.CrmEntries.CrmEntry do
  @moduledoc """
  Ledgr-owned operator overlay for an AMP conversation. One row per
  `conversation_id`. Holds two distinct sets of operator annotations
  on the same table — they're independent and can be set without
  each other:

  ## 1. Traditional CRM pipeline (operator's lead funnel)
    * `contact_stage` — where in the contact lifecycle (cold/warm/etc)
    * `sales_stage`   — where in the sales pipeline

  ## 2. Four-axis state model (operator's mirror of bot state machine)
    * `funnel_stage`            — lifecycle position
    * `qualification_verdict`   — diagnostic outcome (nullable)
    * `escalation_status`       — live-agent track (nullable)
    * `engagement_health`       — stuck-signal axis (nullable)

  These two groupings are **independent** by design. The CRM pipeline
  is the operator's own pipeline view; the four axes are the
  operator's overlay of the bot's planned state machine — eventually
  to be reconciled with bot-canonical columns on `conversations`.

  ## Editing values

  Each enum below is a list of `{code, label_es}` pairs — single
  source of truth. Reordering or adding/removing a value is a one-line
  change. Bot-side migrations do not need to match these.
  """

  use Ecto.Schema
  import Ecto.Changeset

  # ── CRM pipeline ─────────────────────────────────────────────────────

  @contact_stages [
    {"not_contacted", "Sin contactar"},
    {"contacted", "Contactado"},
    {"unresponsive", "No contesta"},
    {"customer", "Cliente"},
    {"lost", "Perdido"}
  ]

  @sales_stages [
    {"prospect", "Prospecto"},
    {"qualified", "Calificado"},
    {"proposal_sent", "Propuesta enviada"},
    {"negotiation", "Negociación"},
    {"won", "Ganada"},
    {"lost", "Perdida"}
  ]

  # ── Four-axis state model ────────────────────────────────────────────

  @funnel_stages [
    {"intake", "Intake"},
    {"qualifying", "Calificando"},
    {"terminal", "Veredicto"},
    {"escalating", "Escalando"},
    {"closed", "Cerrado"}
  ]

  @qualification_verdicts [
    {"qualifies_m40", "Califica M40"},
    {"qualifies_m44", "Califica M44"},
    {"does_not_qualify", "No califica"},
    {"already_pensionado", "Ya pensionado"},
    {"ley_97", "Ley 97"},
    {"regime_unknown", "Régimen desconocido"},
    {"edge_case", "Caso especial"},
    {"consent_declined", "Sin consentimiento"}
  ]

  @escalation_statuses [
    {"offered", "Ofrecido"},
    {"declined", "Rechazado"},
    {"payment_pending", "Pago pendiente"},
    {"paid", "Pagado"},
    {"data_review", "Revisión de datos"},
    {"searching", "Buscando agente"},
    {"connected", "Conectado"},
    {"complete", "Completo"}
  ]

  @engagement_healths [
    {"active", "Activo"},
    {"stalled", "Estancado"},
    {"disengaged", "Desconectado"}
  ]

  schema "conversation_crm" do
    field :conversation_id, :string

    # CRM pipeline
    field :contact_stage, :string
    field :sales_stage, :string

    # Four-axis state
    field :funnel_stage, :string
    field :qualification_verdict, :string
    field :escalation_status, :string
    field :engagement_health, :string

    timestamps(type: :utc_datetime)
  end

  @cast_fields ~w(
    conversation_id
    contact_stage
    sales_stage
    funnel_stage
    qualification_verdict
    escalation_status
    engagement_health
  )a

  def changeset(entry, attrs) do
    entry
    |> cast(normalize(attrs), @cast_fields)
    |> validate_required([:conversation_id])
    |> validate_inclusion(:contact_stage, codes(@contact_stages))
    |> validate_inclusion(:sales_stage, codes(@sales_stages))
    |> validate_inclusion(:funnel_stage, codes(@funnel_stages))
    |> validate_inclusion(:qualification_verdict, codes(@qualification_verdicts))
    |> validate_inclusion(:escalation_status, codes(@escalation_statuses))
    |> validate_inclusion(:engagement_health, codes(@engagement_healths))
    |> unique_constraint(:conversation_id)
  end

  # Form selects submit "" for the blank option; treat as "clear".
  defp normalize(attrs) do
    Map.new(attrs, fn {k, v} -> {k, if(v == "", do: nil, else: v)} end)
  end

  defp codes(pairs), do: Enum.map(pairs, &elem(&1, 0))

  defp label_for(pairs, value) do
    Enum.find_value(pairs, value, fn {code, label} ->
      if code == value, do: label
    end)
  end

  defp options(pairs), do: Enum.map(pairs, fn {code, label} -> {label, code} end)

  # ── Public helpers per field ─────────────────────────────────────────

  # CRM pipeline
  def contact_stage_codes, do: codes(@contact_stages)
  def sales_stage_codes, do: codes(@sales_stages)

  def contact_stage_label(nil), do: nil
  def contact_stage_label(code), do: label_for(@contact_stages, code)

  def sales_stage_label(nil), do: nil
  def sales_stage_label(code), do: label_for(@sales_stages, code)

  def contact_stage_options, do: options(@contact_stages)
  def sales_stage_options, do: options(@sales_stages)

  # Four-axis state
  def funnel_stage_codes, do: codes(@funnel_stages)
  def qualification_verdict_codes, do: codes(@qualification_verdicts)
  def escalation_status_codes, do: codes(@escalation_statuses)
  def engagement_health_codes, do: codes(@engagement_healths)

  def funnel_stage_label(nil), do: nil
  def funnel_stage_label(code), do: label_for(@funnel_stages, code)

  def qualification_verdict_label(nil), do: nil
  def qualification_verdict_label(code), do: label_for(@qualification_verdicts, code)

  def escalation_status_label(nil), do: nil
  def escalation_status_label(code), do: label_for(@escalation_statuses, code)

  def engagement_health_label(nil), do: nil
  def engagement_health_label(code), do: label_for(@engagement_healths, code)

  def funnel_stage_options, do: options(@funnel_stages)
  def qualification_verdict_options, do: options(@qualification_verdicts)
  def escalation_status_options, do: options(@escalation_statuses)
  def engagement_health_options, do: options(@engagement_healths)
end
