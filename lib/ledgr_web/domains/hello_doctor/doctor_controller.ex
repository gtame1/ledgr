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

  def new(conn, _params) do
    changeset = Doctors.change_doctor(%Ledgr.Domains.HelloDoctor.Doctors.Doctor{})

    render(conn, :new,
      changeset: changeset,
      specialty_options: Doctors.specialty_options()
    )
  end

  def create(conn, %{"doctor" => doctor_params}) do
    case Doctors.create_doctor(doctor_params) do
      {:ok, doctor} ->
        conn
        |> put_flash(:info, "Doctor created successfully.")
        |> redirect(to: dp(conn, "/doctors/#{doctor.id}"))

      {:error, changeset} ->
        render(conn, :new,
          changeset: changeset,
          specialty_options: Doctors.specialty_options()
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    doctor = Doctors.get_doctor!(id)
    changeset = Doctors.change_doctor(doctor)

    render(conn, :edit,
      doctor: doctor,
      changeset: changeset,
      specialty_options: Doctors.specialty_options()
    )
  end

  def update(conn, %{"id" => id, "doctor" => doctor_params}) do
    doctor = Doctors.get_doctor!(id)

    case Doctors.update_doctor(doctor, doctor_params) do
      {:ok, doctor} ->
        conn
        |> put_flash(:info, "Doctor updated successfully.")
        |> redirect(to: dp(conn, "/doctors/#{doctor.id}"))

      {:error, changeset} ->
        render(conn, :edit,
          doctor: doctor,
          changeset: changeset,
          specialty_options: Doctors.specialty_options()
        )
    end
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
