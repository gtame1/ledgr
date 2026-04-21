defmodule LedgrWeb.Domains.AumentaMiPension.PensionCaseController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.PensionCases

  def index(conn, params) do
    cases =
      PensionCases.list_pension_cases(
        qualifies: params["qualifies"],
        modalidad: params["modalidad"],
        search: params["search"]
      )

    render(conn, :index,
      pension_cases: cases,
      modalidad_options: PensionCases.modalidad_options(),
      current_qualifies: params["qualifies"],
      current_modalidad: params["modalidad"],
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id}) do
    pension_case = PensionCases.get_pension_case!(id)
    render(conn, :show, pension_case: pension_case)
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.PensionCaseHTML do
  use LedgrWeb, :html
  embed_templates "pension_case_html/*"

  @doc """
  Parses `media_analyses` (stored by the Python backend as a JSON string
  containing a list of per-attachment analysis entries) into a list of maps.

  Returns `[]` when the value is nil, blank, or malformed JSON — the template
  hides the section on empty result.
  """
  def parse_media_analyses(nil), do: []
  def parse_media_analyses(""), do: []

  def parse_media_analyses(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, list} when is_list(list) -> list
      {:ok, map} when is_map(map) -> [map]
      _ -> []
    end
  end

  def parse_media_analyses(list) when is_list(list), do: list
  def parse_media_analyses(_), do: []

  @doc "Human-readable label for the `type` field on a media analysis entry."
  def media_type_label("MEDICAL_DOCUMENT"), do: "Documento"
  def media_type_label("TEXT"), do: "Texto / OCR"
  def media_type_label("IMAGE"), do: "Imagen"
  def media_type_label(nil), do: "Adjunto"
  def media_type_label(other) when is_binary(other), do: other
  def media_type_label(_), do: "Adjunto"
end
