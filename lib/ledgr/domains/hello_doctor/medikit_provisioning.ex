defmodule Ledgr.Domains.HelloDoctor.MedikitProvisioning do
  @moduledoc """
  One-off backfill that provisions Hello Doctor doctors as Medikit
  HealthcareProviders (migrating off Prescrypto).

  Invoke manually — there is no GenServer and no application supervision
  entry. From a console / release shell:

      Ledgr.Domains.HelloDoctor.MedikitProvisioning.run()

  For each candidate doctor — `deactivated_at IS NULL`, `terms_accepted = true`,
  and `medikit_healthcare_provider_id IS NULL` (so re-running is idempotent: a
  doctor already provisioned is skipped) — it:

    1. POST /doctors/validate-professional-license with the cédula.
    2. If valid, POST /doctors (identity + account-scoped ids) → HealthcareProvider id.
    3. UPDATE doctors SET medikit_healthcare_provider_id, medikit_license_validated_at
       (only those two columns) WHERE id = doctor.id.

  Fail-closed per doctor: a missing cédula, invalid license, failed validate /
  register, or DB write error leaves `medikit_healthcare_provider_id` NULL —
  never a placeholder — so the next run retries that doctor. One doctor's
  failure never aborts the batch.
  """
  require Logger
  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Medikit
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor

  @doc """
  Runs the backfill over every candidate doctor. Returns a summary map:

      %{total: n, provisioned: n, invalid_license: n, incomplete: n, failed: n,
        results: [{doctor_id, outcome}, ...]}

  where `outcome` is `{:provisioned, hp_id}`, `:invalid_license`,
  `{:incomplete, missing_fields}`, or `{:error, reason}`.
  """
  def run do
    Repo.put_active_repo(Ledgr.Repos.HelloDoctor)

    doctors = Repo.all(candidates_query())
    Logger.info("[Medikit] Provisioning backfill starting — #{length(doctors)} candidate(s)")

    results = Enum.map(doctors, fn d -> {d.id, provision(d)} end)
    summary = summarize(doctors, results)

    Logger.info(
      "[Medikit] Provisioning backfill done — " <>
        "provisioned=#{summary.provisioned} invalid_license=#{summary.invalid_license} " <>
        "incomplete=#{summary.incomplete} failed=#{summary.failed} total=#{summary.total}"
    )

    summary
  end

  # Active doctors not yet provisioned in Medikit.
  defp candidates_query do
    from d in Doctor,
      where:
        is_nil(d.deactivated_at) and
          d.terms_accepted == true and
          is_nil(d.medikit_healthcare_provider_id)
  end

  defp provision(%Doctor{} = doctor) do
    # Pre-flight: skip doctors missing any RAML-required field before we make
    # any API call. Keeps the column NULL (fail-closed) and tells the operator
    # exactly which fields to fill in the doctor form.
    case Medikit.missing_register_fields(doctor) do
      [] ->
        validate_then_register(doctor)

      missing ->
        Logger.info(
          "[Medikit] Doctor #{doctor.id}: incomplete — missing #{Enum.join(missing, ", ")}"
        )

        {:incomplete, missing}
    end
  end

  defp validate_then_register(%Doctor{} = doctor) do
    case Medikit.validate_professional_license(doctor) do
      {:ok, :valid} ->
        register_and_write(doctor)

      {:ok, :invalid} ->
        Logger.info("[Medikit] Doctor #{doctor.id}: license invalid — left unprovisioned")
        :invalid_license

      {:error, reason} ->
        Logger.warning("[Medikit] Doctor #{doctor.id}: validate failed — #{inspect(reason)}")
        {:error, {:validate_failed, reason}}
    end
  end

  defp register_and_write(%Doctor{} = doctor) do
    case Medikit.register_doctor(doctor) do
      {:ok, healthcare_provider_id} ->
        case write_result(doctor, healthcare_provider_id) do
          {:ok, _doctor} ->
            Logger.info("[Medikit] Doctor #{doctor.id}: provisioned (#{healthcare_provider_id})")
            {:provisioned, healthcare_provider_id}

          {:error, changeset} ->
            # Registered in Medikit but our write failed — keep the column NULL
            # so the next run retries. Idempotent on Medikit's side (same
            # SourceSystemIdentifier).
            Logger.error(
              "[Medikit] Doctor #{doctor.id}: registered as #{healthcare_provider_id} but DB write failed — #{inspect(changeset.errors)}"
            )

            {:error, {:db_write_failed, changeset.errors}}
        end

      {:error, reason} ->
        Logger.warning("[Medikit] Doctor #{doctor.id}: register failed — #{inspect(reason)}")
        {:error, {:register_failed, reason}}
    end
  end

  # Writes ONLY the two medikit columns. `Ecto.Changeset.change/2` on the loaded
  # struct emits an UPDATE touching just these fields — the doctors table is
  # never migrated/altered here.
  defp write_result(%Doctor{} = doctor, healthcare_provider_id) do
    doctor
    |> Ecto.Changeset.change(%{
      medikit_healthcare_provider_id: healthcare_provider_id,
      medikit_license_validated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  defp summarize(doctors, results) do
    counts =
      Enum.reduce(results, %{provisioned: 0, invalid_license: 0, incomplete: 0, failed: 0}, fn
        {_id, {:provisioned, _}}, acc -> %{acc | provisioned: acc.provisioned + 1}
        {_id, :invalid_license}, acc -> %{acc | invalid_license: acc.invalid_license + 1}
        {_id, {:incomplete, _}}, acc -> %{acc | incomplete: acc.incomplete + 1}
        {_id, _other}, acc -> %{acc | failed: acc.failed + 1}
      end)

    Map.merge(counts, %{total: length(doctors), results: results})
  end
end
