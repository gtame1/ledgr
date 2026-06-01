defmodule LedgrWeb.Domains.HelloDoctor.PatientController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.Patients

  def index(conn, params) do
    # Patients.list_patients/1 takes a keyword list (uses opts[:search] under
    # the hood). Passing the raw string here crashes Access on any non-empty
    # search.
    patients = Patients.list_patients(search: params["search"])

    render(conn, :index,
      patients: patients,
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id}) do
    patient = Patients.get_patient!(id)

    render(conn, :show, patient: patient)
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
end

defmodule LedgrWeb.Domains.HelloDoctor.PatientHTML do
  use LedgrWeb, :html
  embed_templates "patient_html/*"
end
