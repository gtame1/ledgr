defmodule Ledgr.Domains.HelloDoctor.Doctors do
  require Logger
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor

  def list_doctors(opts \\ []) do
    Doctor
    |> maybe_filter_available(opts[:status])
    |> maybe_filter_specialty(opts[:specialty])
    |> maybe_filter_deactivated(opts[:deactivated])
    |> maybe_search(opts[:search])
    |> apply_sort(opts[:sort], opts[:dir])
    |> Repo.all()
  end

  # Sortable column headers on the doctor list. `:name` and `:specialty`
  # map to plain columns; `:eligibility` derives from the four bot gates
  # (terms_accepted ∧ is_available ∧ prescrypto_specialty_verified ∧
  # deactivated_at IS NULL) via a CASE so the sort happens in SQL.
  # Falls back to name-asc when sort is unrecognised. Name is the
  # tiebreaker for all non-name sorts.
  defp apply_sort(query, sort, dir) do
    direction = if to_string(dir) == "desc", do: :desc, else: :asc

    case to_string(sort) do
      "specialty" ->
        order_by(query, [d], [{^direction, d.specialty}, asc: d.name])

      "eligibility" ->
        order_by(
          query,
          [d],
          [
            {^direction,
             fragment(
               "CASE WHEN ? AND ? AND ? AND ? IS NULL THEN 1 ELSE 0 END",
               d.terms_accepted,
               d.is_available,
               d.prescrypto_specialty_verified,
               d.deactivated_at
             )},
            asc: d.name
          ]
        )

      _ ->
        order_by(query, [d], [{^direction, d.name}])
    end
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
      {:ok, result} ->
        updates =
          %{
            prescrypto_medic_id: result.prescrypto_medic_id,
            prescrypto_specialty_verified: result.prescrypto_specialty_verified,
            prescrypto_synced_at: DateTime.utc_now()
          }
          |> then(fn m ->
            if result.prescrypto_token,
              do: Map.put(m, :prescrypto_token, result.prescrypto_token),
              else: m
          end)

        case update_doctor(doctor, updates) do
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

  @doc """
  Toggles the bot-side block on a doctor: setting `deactivated_at` to now
  stops the bot from routing new consultations to them; clearing it
  resumes routing. Distinct from `is_available` (the doctor's own
  "available right now" flag).
  """
  def toggle_deactivation(%Doctor{deactivated_at: nil} = doctor) do
    update_doctor(doctor, %{deactivated_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  def toggle_deactivation(%Doctor{} = doctor) do
    update_doctor(doctor, %{deactivated_at: nil})
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
  defp maybe_filter_available(query, "available"), do: where(query, [d], d.is_available == true)
  defp maybe_filter_available(query, "inactive"), do: where(query, [d], d.is_available == false)

  defp maybe_filter_available(query, "unavailable"),
    do: where(query, [d], d.is_available == false)

  defp maybe_filter_available(query, _), do: query

  # `:deactivated` filter: nil/""/"all" → no filter; "hide" → only
  # active (`deactivated_at IS NULL`); "only" → only deactivated rows.
  defp maybe_filter_deactivated(query, v) when v in [nil, "", "all"], do: query

  defp maybe_filter_deactivated(query, "hide"),
    do: where(query, [d], is_nil(d.deactivated_at))

  defp maybe_filter_deactivated(query, "only"),
    do: where(query, [d], not is_nil(d.deactivated_at))

  defp maybe_filter_deactivated(query, _), do: query

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
