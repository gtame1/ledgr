defmodule Ledgr.Domains.HelloDoctor.Patients do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Patients.Patient

  def list_patients(opts \\ []) do
    Patient
    |> maybe_search(opts[:search])
    |> order_by(desc: :created_at)
    |> Repo.all()
  end

  def get_patient!(id) do
    Patient
    |> Repo.get!(id)
    |> Repo.preload([consultations: [:doctor], medical_records: []])
  end

  def create_patient(attrs) do
    %Patient{}
    |> Patient.changeset(Map.put_new(attrs, "id", Ecto.UUID.generate()))
    |> Repo.insert()
  end

  def update_patient(%Patient{} = patient, attrs) do
    patient
    |> Patient.changeset(attrs)
    |> Repo.update()
  end

  def delete_patient(%Patient{} = patient), do: Repo.delete(patient)

  def change_patient(%Patient{} = patient, attrs \\ %{}), do: Patient.changeset(patient, attrs)

  def patient_options do
    Patient
    |> order_by(:full_name)
    |> Repo.all()
    |> Enum.map(&{Patient.name(&1), &1.id})
  end

  def count_new(start_date, end_date) do
    Patient
    |> where([p], fragment("?::date", p.created_at) >= ^start_date and fragment("?::date", p.created_at) <= ^end_date)
    |> Repo.aggregate(:count)
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query
  defp maybe_search(query, search) do
    term = "%#{search}%"
    where(query, [p], ilike(p.full_name, ^term) or ilike(p.display_name, ^term) or ilike(p.phone, ^term))
  end
end
