defmodule Ledgr.Domains.HelloDoctor.Doctors do
  require Logger
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor

  def list_doctors(opts \\ []) do
    Doctor
    |> maybe_filter_available(opts[:status])
    |> maybe_filter_specialty(opts[:specialty])
    |> maybe_search(opts[:search])
    |> order_by(:name)
    |> Repo.all()
  end

  def get_doctor!(id) do
    Doctor
    |> Repo.get!(id)
    |> Repo.preload(consultations: :patient)
  end

  def create_doctor(attrs) do
    result =
      %Doctor{}
      |> Doctor.changeset(Map.put_new(attrs, "id", Ecto.UUID.generate()))
      |> Repo.insert()

    case result do
      {:ok, doctor} ->
        doctor = maybe_sync_prescrypto(doctor)
        {:ok, doctor}

      error ->
        error
    end
  end

  defp maybe_sync_prescrypto(%Doctor{email: nil} = doctor) do
    Logger.info("[Prescrypto] Skipping sync for doctor #{doctor.id} — email missing")
    doctor
  end

  defp maybe_sync_prescrypto(%Doctor{cedula_profesional: nil} = doctor) do
    Logger.info("[Prescrypto] Skipping sync for doctor #{doctor.id} — cedula_profesional missing")
    doctor
  end

  defp maybe_sync_prescrypto(doctor) do
    alias Ledgr.Domains.HelloDoctor.Prescrypto

    case Prescrypto.create_medic(doctor) do
      {:ok, %{prescrypto_medic_id: medic_id, prescrypto_token: medic_token}} ->
        case update_doctor(doctor, %{
               prescrypto_medic_id: medic_id,
               prescrypto_token: medic_token,
               prescrypto_synced_at: DateTime.utc_now()
             }) do
          {:ok, updated} -> updated
          {:error, _} -> doctor
        end

      {:error, reason} when reason != :disabled ->
        Logger.warning("[Prescrypto] Sync failed for doctor #{doctor.id}: #{inspect(reason)}")
        doctor

      {:error, :disabled} ->
        doctor
    end
  end

  def update_doctor(%Doctor{} = doctor, attrs) do
    doctor
    |> Doctor.changeset(attrs)
    |> Repo.update()
  end

  def delete_doctor(%Doctor{} = doctor), do: Repo.delete(doctor)

  def change_doctor(%Doctor{} = doctor, attrs \\ %{}), do: Doctor.changeset(doctor, attrs)

  def toggle_availability(%Doctor{} = doctor) do
    update_doctor(doctor, %{is_available: !doctor.is_available})
  end

  def count_by_status(:active),
    do: Doctor |> where([d], d.is_available == true) |> Repo.aggregate(:count)

  def count_by_status(:inactive),
    do: Doctor |> where([d], d.is_available == false) |> Repo.aggregate(:count)

  def count_by_status(_), do: Repo.aggregate(Doctor, :count)

  def count_all, do: Repo.aggregate(Doctor, :count)

  def top_by_consultations(limit) do
    from(d in Doctor,
      left_join: c in assoc(d, :consultations),
      where: d.is_available == true,
      group_by: d.id,
      order_by: [desc: count(c.id)],
      select: %{d | years_experience: d.years_experience},
      select_merge: %{years_experience: count(c.id)},
      limit: ^limit
    )
    |> Repo.all()
  end

  def doctor_options do
    Doctor
    |> where([d], d.is_available == true)
    |> order_by(:name)
    |> Repo.all()
    |> Enum.map(&{&1.name, &1.id})
  end

  def specialty_options do
    Ledgr.Domains.HelloDoctor.Specialties.specialty_options()
  end

  def specialties, do: specialty_options()

  defp maybe_filter_available(query, nil), do: query
  defp maybe_filter_available(query, ""), do: query
  defp maybe_filter_available(query, "active"), do: where(query, [d], d.is_available == true)
  defp maybe_filter_available(query, "inactive"), do: where(query, [d], d.is_available == false)
  defp maybe_filter_available(query, _), do: query

  defp maybe_filter_specialty(query, nil), do: query
  defp maybe_filter_specialty(query, ""), do: query
  defp maybe_filter_specialty(query, specialty), do: where(query, [d], d.specialty == ^specialty)

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    term = "%#{search}%"
    where(query, [d], ilike(d.name, ^term) or ilike(d.phone, ^term) or ilike(d.email, ^term))
  end
end
