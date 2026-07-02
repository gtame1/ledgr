defmodule LedgrWeb.Domains.HelloDoctor.NpsController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.Nps

  def index(conn, _params) do
    render(conn, :index, nps: Nps.overview())
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.NpsHTML do
  use LedgrWeb, :html

  embed_templates "nps_html/*"

  @doc "Color for an NPS score: green ≥ 50, amber ≥ 0, red below."
  def nps_color(nil), do: "var(--text-muted)"
  def nps_color(n) when n >= 50, do: "#16a34a"
  def nps_color(n) when n >= 0, do: "#d97706"
  def nps_color(_), do: "#dc2626"

  @doc "Badge colors for an NPS classification."
  def classification_style("promoter"), do: "background:#dcfce7;color:#166534;"
  def classification_style("passive"), do: "background:#fef9c3;color:#854d0e;"
  def classification_style("detractor"), do: "background:#fee2e2;color:#991b1b;"
  def classification_style(_), do: "background:var(--bg-secondary);color:var(--text-muted);"

  @doc "Human label for a survey status."
  def status_label(status) do
    status |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end
end
