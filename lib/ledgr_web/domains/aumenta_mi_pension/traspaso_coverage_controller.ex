defmodule LedgrWeb.Domains.AumentaMiPension.TraspasoCoverageController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.TraspasoCoverage

  def index(conn, _params) do
    render(conn, :index, metrics: TraspasoCoverage.coverage())
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.TraspasoCoverageHTML do
  use LedgrWeb, :html

  embed_templates "traspaso_coverage_html/*"

  @doc "Percent of `n` over `total`, rounded to a whole number. 0 when total is 0."
  def pct(_n, 0), do: 0
  def pct(_n, nil), do: 0
  def pct(n, total), do: round(n / total * 100)

  @doc """
  The five traspaso requirements, paired with the metric that measures
  each one. `:status` drives the bar color and label in the template:

    * `:ok`      — captured, real count
    * `:partial` — captured but sparse
    * `:proxy`   — no exact field; an approximate proxy count
    * `:missing` — no field exists at all
  """
  def requirements(m) do
    [
      %{
        idx: "1",
        title: "Conocer la AFORE actual",
        field: "checkup_responses.afore_name / has_afore",
        count: m.with_afore,
        status: :partial
      },
      %{
        idx: "2",
        title: "Último cambio de AFORE > 1 año",
        field: "— no capturado en ninguna tabla",
        count: 0,
        status: :missing
      },
      %{
        idx: "3",
        title: "NSS (para validación)",
        field: "customers.nss + checkup_responses.contact_nss",
        count: m.with_nss,
        status: :ok
      },
      %{
        idx: "3",
        title: "CURP (para validación)",
        field: "customers.curp + checkup_responses.contact_curp",
        count: m.with_curp,
        status: :ok
      },
      %{
        idx: "4",
        title: "No estar en lista de exclusión",
        field: "— no capturado en ninguna tabla",
        count: 0,
        status: :missing
      },
      %{
        idx: "5",
        title: "Comprobante de domicilio + ID oficial",
        field: "sin campo estructurado · proxy: pension_cases.media_analyses",
        count: m.media_cases,
        status: :proxy
      }
    ]
  end

  @doc """
  Pension-eligibility signals (independent of the 5 traspaso requisites).
  Each is a count of leads matching a profile, paired with the count of
  leads for which we actually know that signal (the honest denominator,
  since coverage is sparse).
  """
  def eligibility(m) do
    [
      %{
        title: "Mayores de 60 años",
        field: "edad > 60 · de date_of_birth / contact_birth_date / pension_cases.age",
        count: m.over_60,
        known: m.age_known
      },
      %{
        title: "Más de 850 semanas cotizadas",
        field: "weeks_contributed > 850 · máx. entre customers / checkup / pension_cases",
        count: m.weeks_over_850,
        known: m.weeks_known
      },
      %{
        title: "1+ año sin cotizar / trabajar",
        field: "última cotización > 1 año · last_imss_contribution_date / last_year_cotized",
        count: m.inactive_1yr,
        known: m.activity_known
      }
    ]
  end

  @doc """
  Inline bar/label color for a requirement status, mapped to the AMP
  brand palette (Brand Manual v1.1 — verde bosque + crema + tierra):

    * `:ok`      → `--primary`      (Verde Bosque, "lo tenemos")
    * `:partial` → mostaza/tierra    (warm amber that fits the earthy palette)
    * `:proxy`   → `--text-muted`    (Tierra Medio, "aproximado")
    * `:missing` → `--ct-error`      (brand error red)
  """
  def status_color(:ok), do: "var(--primary)"
  def status_color(:partial), do: "#B07D2B"
  def status_color(:proxy), do: "var(--text-muted)"
  def status_color(:missing), do: "var(--ct-error, #dc2626)"
end
