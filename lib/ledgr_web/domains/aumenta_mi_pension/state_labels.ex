defmodule LedgrWeb.Domains.AumentaMiPension.StateLabels.Helpers do
  @moduledoc """
  Shared Spanish-language label helpers for AMP state vocabularies.

  Functions are auto-imported into HEEx templates of any HTML module
  that does `use LedgrWeb.Domains.AumentaMiPension.StateLabels` — see
  the wrapper module below.

  Covers:

    * **`funnel_stage_label/1`** — labels for the **bot's**
      `conversations.funnel_stage` column. Mid-migration vocabulary
      (legacy values + new four-axis values) all map here.
    * **`qualification_verdict_label/1`**, **`escalation_status_label/1`**,
      **`engagement_health_label/1`** — wrappers over the canonical
      label maps on
      `Ledgr.Domains.AumentaMiPension.CrmEntries.CrmEntry`.

  This module exists because two HTML modules need the same helpers
  (conversation show + the new lead show), and HEEx forbids `alias`
  inside templates so we can't just FQN the calls.
  """

  alias Ledgr.Domains.AumentaMiPension.CrmEntries.CrmEntry

  @funnel_labels %{
    # Legacy vocabulary the bot wrote for ~a year. Still on most rows.
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
    "completed" => "Completada",
    # New four-axis vocabulary (bot started writing 2026-05-23).
    "intake" => "Intake",
    "qualifying" => "Calificando",
    "terminal" => "Veredicto",
    "escalating" => "Escalando",
    "closed" => "Cerrado"
  }

  @doc """
  Human-readable Spanish label for a **bot** funnel stage. Falls back
  to a title-cased version of the raw value when an unknown stage
  shows up (so unmapped bot output renders rather than blanking).
  """
  def funnel_stage_label(nil), do: "---"

  def funnel_stage_label(stage) when is_binary(stage) do
    Map.get_lazy(@funnel_labels, stage, fn ->
      stage |> String.replace("_", " ") |> String.capitalize()
    end)
  end

  def funnel_stage_label(stage), do: funnel_stage_label(to_string(stage))

  # Thin wrappers — canonical maps live on CrmEntry so the label
  # vocabulary stays adjacent to the enum it labels.
  def qualification_verdict_label(code), do: CrmEntry.qualification_verdict_label(code)
  def escalation_status_label(code), do: CrmEntry.escalation_status_label(code)
  def engagement_health_label(code), do: CrmEntry.engagement_health_label(code)
end

defmodule LedgrWeb.Domains.AumentaMiPension.StateLabels do
  @moduledoc """
  `use` this in any HTML module that needs the AMP state-label helpers
  available in its embedded HEEx templates:

      defmodule LedgrWeb.Domains.AumentaMiPension.FooHTML do
        use LedgrWeb, :html
        use LedgrWeb.Domains.AumentaMiPension.StateLabels
        embed_templates "foo_html/*"
      end

  Then `funnel_stage_label/1`, `qualification_verdict_label/1`,
  `escalation_status_label/1`, and `engagement_health_label/1` are
  callable by short name inside any `*.heex` under that module.
  """

  defmacro __using__(_opts) do
    quote do
      import LedgrWeb.Domains.AumentaMiPension.StateLabels.Helpers
    end
  end
end
