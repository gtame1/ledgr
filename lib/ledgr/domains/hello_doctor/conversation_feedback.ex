defmodule Ledgr.Domains.HelloDoctor.ConversationFeedback do
  @moduledoc """
  The failure taxonomy for HelloDoctor conversation feedback.

  Deliberately lives HERE (the UI layer) and not in the bot: the bot
  stores `failure_category` as a free string (bot ADR-059), so refining
  this list — expected after the error-analysis seeding session — is a
  ledgr-only change, no bot deploy.

  Each entry is `{value, label}`: `value` is what's persisted on the
  bot's `conversations.failure_category`; `label` is what the operator
  sees in the dropdown. Keep values stable once data exists against
  them — relabel freely, rename values only with a backfill.
  """

  @failure_categories [
    {"missed_escalation", "Escalación de seguridad omitida o tardía"},
    {"unsafe_clinical_content", "Contenido clínico inseguro (profundidad / receta)"},
    {"funnel_regression", "Retroceso o loop de funnel"},
    {"data_collection_loop", "Re-pregunta datos que ya tenía"},
    {"wrong_tone", "Tono robótico / maquinaria en momento sensible"},
    {"hallucinated_capability", "Prometió algo que no puede hacer"},
    {"wrong_info", "Información incorrecta (precio / proceso / empresa)"},
    {"payment_flow_error", "Error en el flujo de pago"},
    {"missed_conversion", "No capitalizó el momento de conversión"},
    {"other", "Otro (explicar en la nota)"}
  ]

  def failure_categories, do: @failure_categories

  @doc "Label for a stored category value; falls back to the raw value."
  def category_label(nil), do: nil

  def category_label(value) do
    case List.keyfind(@failure_categories, value, 0) do
      {_, label} -> label
      nil -> value
    end
  end
end
