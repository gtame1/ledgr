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
end

defmodule LedgrWeb.Domains.HelloDoctor.PatientHTML do
  use LedgrWeb, :html
  embed_templates "patient_html/*"
end
