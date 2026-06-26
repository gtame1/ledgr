defmodule LedgrWeb.Domains.HelloDoctor.PatientController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.Patients
  alias Ledgr.Domains.HelloDoctor.PatientSegments

  @empty_tier %{tier: "L0", inbound_messages: 0, consult_count: 0}

  def index(conn, params) do
    # Patients.list_patients/1 takes a keyword list (uses opts[:search] under
    # the hood). Passing the raw string here crashes Access on any non-empty
    # search.
    all = Patients.list_patients(search: params["search"])
    tmap = PatientSegments.tiers_map(Enum.map(all, & &1.id))

    annotated = Enum.map(all, fn p -> {p, Map.get(tmap, p.id, @empty_tier)} end)
    counts = Enum.frequencies_by(annotated, fn {_p, t} -> t.tier end)

    # Default to actual patients (L1+); L0 leads are "not counted as patients".
    current_tier = params["tier"] || "patients"
    patients = Enum.filter(annotated, fn {_p, t} -> tier_match?(current_tier, t.tier) end)

    render(conn, :index,
      patients: patients,
      counts: counts,
      current_tier: current_tier,
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id}) do
    patient = Patients.get_patient!(id)
    tier = PatientSegments.tier_for(patient.id) || @empty_tier

    render(conn, :show, patient: patient, tier: tier)
  end

  @doc "Materializes the patient_segments snapshot the bot reads."
  def recompute_tiers(conn, _params) do
    counts = PatientSegments.recompute()
    total = counts |> Map.values() |> Enum.sum()

    conn
    |> put_flash(
      :info,
      "Recomputed tiers for #{total} patients — " <>
        "L1 #{counts["L1"] || 0} · L2 #{counts["L2"] || 0} · L3 #{counts["L3"] || 0} · L0 #{counts["L0"] || 0} leads."
    )
    |> redirect(to: dp(conn, "/patients"))
  end

  def edit(conn, %{"id" => id}) do
    patient = Patients.get_patient!(id)
    changeset = Patients.change_patient_editable(patient)

    render(conn, :edit, patient: patient, changeset: changeset)
  end

  def update(conn, %{"id" => id, "patient" => patient_params}) do
    patient = Patients.get_patient!(id)

    case Patients.update_patient_editable(patient, patient_params) do
      {:ok, updated} ->
        conn
        |> put_flash(:info, "Patient updated.")
        |> redirect(to: dp(conn, "/patients/#{updated.id}"))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Failed to update patient.")
        |> render(:edit, patient: patient, changeset: changeset)
    end
  end

  defp tier_match?("all", _tier), do: true
  defp tier_match?("patients", tier), do: tier in ~w[L1 L2 L3]
  defp tier_match?("leads", tier), do: tier == "L0"
  defp tier_match?(filter, tier), do: filter == tier
end

defmodule LedgrWeb.Domains.HelloDoctor.PatientHTML do
  use LedgrWeb, :html
  embed_templates "patient_html/*"

  alias Ledgr.Domains.HelloDoctor.PatientSegments

  @doc "Inline tier badge (colored pill) for a tier key like \"L2\"."
  def tier_badge(assigns) do
    assigns = assign(assigns, :meta, PatientSegments.tier_meta(assigns.tier))

    ~H"""
    <span
      class="text-xs font-semibold"
      style={"display:inline-block;padding:0.1rem 0.5rem;border-radius:9999px;white-space:nowrap;background:#{@meta.color}1f;color:#{@meta.color};"}
      title={@meta.label}
    >
      {@meta.label}
    </span>
    """
  end
end
