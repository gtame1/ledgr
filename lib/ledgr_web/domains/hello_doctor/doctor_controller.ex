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
        conn =
          if is_nil(doctor.prescrypto_medic_id) do
            put_flash(
              conn,
              :warning,
              "Doctor created, but Prescrypto sync failed — retry from the doctor page."
            )
          else
            conn
          end

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

  def retry_prescrypto_sync(conn, %{"id" => id}) do
    doctor = Doctors.get_doctor!(id)

    case Ledgr.Domains.HelloDoctor.Prescrypto.create_medic(doctor) do
      {:ok, %{prescrypto_medic_id: medic_id, prescrypto_token: medic_token}} ->
        {:ok, _} =
          Doctors.update_doctor(doctor, %{
            prescrypto_medic_id: medic_id,
            prescrypto_token: medic_token,
            prescrypto_synced_at: DateTime.utc_now()
          })

        conn
        |> put_flash(:info, "Prescrypto sync successful (medic ##{medic_id}).")
        |> redirect(to: dp(conn, "/doctors/#{id}"))

      {:error, {:api_error, _status, errors}} ->
        conn
        |> put_flash(:error, "Prescrypto sync failed: #{format_prescrypto_errors(errors)}")
        |> redirect(to: dp(conn, "/doctors/#{id}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Prescrypto sync failed: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/doctors/#{id}"))
    end
  end

  defp format_prescrypto_errors(errors) when is_map(errors) do
    errors
    |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(List.wrap(msgs), ", ")}" end)
    |> Enum.join("; ")
  end

  defp format_prescrypto_errors(other), do: inspect(other)

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

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {k, v}, acc ->
              String.replace(acc, "%{#{k}}", to_string(v))
            end)
          end)

        conn
        |> put_flash(:error, "Failed to update availability: #{inspect(errors)}")
        |> redirect(to: dp(conn, "/doctors/#{id}"))
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.DoctorHTML do
  use LedgrWeb, :html
  embed_templates "doctor_html/*"
end
