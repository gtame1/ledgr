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
  # (terms_accepted ∧ is_available ∧ medikit_healthcare_provider_id IS NOT NULL ∧
  # deactivated_at IS NULL) via a CASE so the sort happens in SQL. The
  # prescribing gate is Medikit provisioning (bot ADR-070), which replaced the
  # legacy Prescrypto cédula-verification gate.
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
               "CASE WHEN ? AND ? AND ? IS NOT NULL AND ? IS NULL THEN 1 ELSE 0 END",
               d.terms_accepted,
               d.is_available,
               d.medikit_healthcare_provider_id,
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
        # Stamp extension_code + referral_link immediately so the doctor
        # is patient-shareable without waiting for the bot's next
        # startup-time backfill. Mirrors the bot's doctor_codes module.
        doctor = Ledgr.Domains.HelloDoctor.DoctorCodes.stamp_missing!(doctor)
        doctor = maybe_provision_medikit(doctor)
        {:ok, doctor}

      error ->
        error
    end
  end

  # Prescrypto provisioning has been retired in favor of Medikit (bot ADR-070).
  # On create we best-effort provision the doctor in Medikit — the doctor form
  # captures all required Medikit fields, so a fully-filled doctor is registered
  # immediately. Any failure (Medikit disabled, incomplete fields, cédula not
  # yet validatable) is swallowed and leaves `medikit_healthcare_provider_id`
  # NULL; the admin can retry via the "Provision with Medikit" button or the
  # `mix hd.medikit_provision` backfill. Never blocks doctor creation.
  defp maybe_provision_medikit(%Doctor{} = doctor) do
    if Ledgr.Domains.HelloDoctor.Medikit.enabled?() do
      case Ledgr.Domains.HelloDoctor.MedikitProvisioning.provision_doctor(doctor) do
        {:provisioned, _hp_id} ->
          Repo.get(Doctor, doctor.id) || doctor

        outcome ->
          Logger.info(
            "[Medikit] Doctor #{doctor.id} not provisioned on create — #{inspect(outcome)}"
          )

          doctor
      end
    else
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

  @doc """
  Flips the admin-managed `has_correct_rfc` flag. No eligibility impact —
  the flag exists for CFDI / invoicing readiness reporting only.
  """
  def toggle_correct_rfc(%Doctor{} = doctor) do
    update_doctor(doctor, %{has_correct_rfc: !doctor.has_correct_rfc})
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
