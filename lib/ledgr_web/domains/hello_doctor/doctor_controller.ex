defmodule LedgrWeb.Domains.HelloDoctor.DoctorController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.Doctors

  def index(conn, params) do
    filters = %{
      status: params["status"],
      search: params["search"]
    }

    doctors = Doctors.list_doctors(filters)

    render(conn, :index,
      doctors: doctors,
      current_status: params["status"],
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id}) do
    doctor = Doctors.get_doctor!(id)

    render(conn, :show, doctor: doctor)
  end

  def toggle_status(conn, %{"id" => id}) do
    doctor = Doctors.get_doctor!(id)

    case Doctors.toggle_availability(doctor) do
      {:ok, doctor} ->
        status_label = if doctor.is_available, do: "available", else: "unavailable"

        conn
        |> put_flash(:info, "Doctor is now #{status_label}.")
        |> redirect(to: dp(conn, "/doctors/#{doctor.id}"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to update doctor availability.")
        |> redirect(to: dp(conn, "/doctors/#{id}"))
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.DoctorHTML do
  use LedgrWeb, :html
  embed_templates "doctor_html/*"
end
