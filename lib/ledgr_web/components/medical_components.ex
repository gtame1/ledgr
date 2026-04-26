defmodule LedgrWeb.MedicalComponents do
  @moduledoc """
  HEEx components for HelloDoctor / AumentaMiPension medical record fields.
  """
  use Phoenix.Component

  @doc """
  Renders the `possible_conditions` field of a `MedicalRecord`.

  The field is stored as `:string`. Two formats are supported:

    * **JSON list of maps** (current AI output) — each map has `"condition"`,
      and optionally `"confidence"` (high/medium/low) and `"icd10"`. Renders
      as a stack of pills with confidence color-coded.
    * **Plain text / legacy comma-separated** — rendered as-is.
  """
  attr :value, :string, required: true

  def possible_conditions(assigns) do
    parsed =
      case Jason.decode(assigns.value || "") do
        {:ok, list} when is_list(list) ->
          if Enum.all?(list, &(is_map(&1) and Map.has_key?(&1, "condition"))), do: list, else: nil

        _ ->
          nil
      end

    assigns = assign(assigns, :parsed, parsed)

    ~H"""
    <%= if @parsed do %>
      <div class="flex flex-col gap-1.5">
        <div :for={c <- @parsed} class="flex items-center gap-2 flex-wrap">
          <span class="text-sm font-medium" style="color: var(--text-main);">
            {c["condition"]}
          </span>
          <%= if c["icd10"] do %>
            <span class="text-xs px-1.5 py-0.5 rounded font-mono" style="background: rgba(0,0,0,0.04); color: var(--text-muted);">
              {c["icd10"]}
            </span>
          <% end %>
          <%= if c["confidence"] do %>
            <span class={"text-xs px-2 py-0.5 rounded-full font-medium #{confidence_class(c["confidence"])}"}>
              {String.capitalize(to_string(c["confidence"]))}
            </span>
          <% end %>
        </div>
      </div>
    <% else %>
      {@value}
    <% end %>
    """
  end

  defp confidence_class("high"), do: "bg-emerald-100 text-emerald-800"
  defp confidence_class("medium"), do: "bg-amber-100 text-amber-800"
  defp confidence_class("low"), do: "bg-slate-100 text-slate-700"
  defp confidence_class(_), do: "bg-slate-100 text-slate-700"
end
