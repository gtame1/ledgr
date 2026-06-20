defmodule Ledgr.Domains.HelloDoctor.Medikit do
  @moduledoc """
  Client for Medikit's doctors API (doctors-1.0.38 RAML), used to migrate
  Hello Doctor off Prescrypto for digital prescriptions.

  Auth is a single account-level `API-KEY` header (not per-doctor). All calls go
  to the configured `base_url` (dev/UAT). Config from
  `Application.get_env(:ledgr, :medikit)`:

      base_url        — doctors host (UAT: https://api-doctors-1jqz1q.5sc6y6-2.usa-e2.cloudhub.io/api)
      api_key         — account API-KEY header value
      enabled         — false short-circuits every call with {:error, :disabled}

      # account-scoped ids (from Medikit Account Manager)
      payer           — Payer            (required by /doctors)
      purchaser_plan  — PurchaserPlan    (required by /doctors)
      organization_id — OrganizationId   (optional)
      source_system   — SourceSystem     (optional; required to send SourceSystemIdentifier)
      country         — Country          (default "MX")
      specialty_catalog — see MedikitSpecialties

  Every other value Medikit needs is now stored per-doctor on the `doctors`
  table (first_name / paternal_surname / maternal_surname / birthdate / gender /
  tax_id / address_* / medikit_specialty_id). `MedikitProvisioning` checks those
  are present before calling — see `missing_register_fields/1`.

  Both operations fail-closed: any non-success → {:error, _}; the caller leaves
  `medikit_healthcare_provider_id` NULL, never a placeholder.
  """
  require Logger

  @validate_path "/doctors/validate-professional-license"
  @register_path "/doctors"

  @doc """
  Master "dark switch" for the whole Medikit migration. True only when the
  `:medikit` config is present with a base_url and not explicitly disabled —
  i.e. the `MEDIKIT_*` env vars have been set. Gates both the API client and the
  admin UI so nothing Medikit-related appears or fires until the env is flipped.
  """
  def enabled? do
    cfg = Application.get_env(:ledgr, :medikit, [])
    cfg[:enabled] == true and not blank?(cfg[:base_url])
  end

  @doc """
  Validates a doctor's professional license (cédula) with Medikit.

  POST /doctors/validate-professional-license with the doctor's structured name
  + professionalLicense. A valid cédula returns HTTP 200 `valid:true`; an
  invalid one returns HTTP 400 `valid:false` — both definitive answers →
  `{:ok, :valid | :invalid}`. Any other status / network error is `{:error, _}`.
  """
  def validate_professional_license(%{cedula_profesional: c}) when c in [nil, ""],
    do: {:error, :missing_cedula}

  def validate_professional_license(%{} = doctor) do
    with {:ok, base_url, api_key, _cfg} <- config() do
      body = %{
        "firstName" => doctor.first_name,
        "paternalLastName" => doctor.paternal_surname,
        "maternalLastName" => doctor.maternal_surname,
        "professionalLicense" => doctor.cedula_profesional
      }

      req_opts =
        [url: @validate_path, json: body, headers: headers(api_key)] ++ test_plug_opts()

      case Req.post(Req.new(base_url: base_url), req_opts) do
        {:ok, %{status: 200, body: resp}} ->
          if truthy?(resp["valid"]), do: {:ok, :valid}, else: {:ok, :invalid}

        {:ok, %{status: 400, body: resp}} ->
          Logger.info(
            "[Medikit] Doctor #{doctor.id}: license invalid/rejected — #{inspect(resp["message"] || resp)}"
          )

          {:ok, :invalid}

        {:ok, %{status: status, body: resp}} ->
          Logger.warning(
            "[Medikit] validate-professional-license unexpected status=#{status} body=#{inspect(resp)}"
          )

          {:error, {:unexpected_status, status}}

        {:error, reason} ->
          Logger.warning("[Medikit] validate-professional-license HTTP error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Registers a doctor as a Medikit HealthcareProvider.

  POST /doctors with the doctor identity + account-scoped ids, and
  `SourceSystemIdentifier` set to our `doctors.id`. On success the RAML returns
  `{"Status":"OK","Data":"<HealthcareProvider id>"}` → `{:ok, id}`. A
  `Status:"Error"` body or non-200 status is `{:error, _}` (fail-closed).
  """
  def register_doctor(%{} = doctor) do
    case missing_register_fields(doctor) do
      [] ->
        do_register(doctor)

      missing ->
        {:error, {:incomplete, missing}}
    end
  end

  defp do_register(doctor) do
    with {:ok, base_url, api_key, cfg} <- config() do
      req_opts =
        [url: @register_path, json: register_body(doctor, cfg), headers: headers(api_key)] ++
          test_plug_opts()

      case Req.post(Req.new(base_url: base_url), req_opts) do
        {:ok, %{status: 200, body: %{"Status" => "OK", "Data" => id}}}
        when is_binary(id) and id != "" ->
          {:ok, id}

        {:ok, %{status: status, body: resp}} ->
          # Includes 200-with-Status:"Error" and 400 — Data carries the message.
          Logger.warning(
            "[Medikit] register_doctor #{doctor.id} rejected status=#{status} body=#{inspect(resp)}"
          )

          {:error, {:rejected, status, resp}}

        {:error, reason} ->
          Logger.warning("[Medikit] register_doctor #{doctor.id} HTTP error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Returns the list of RAML-required `/doctors` fields that are missing/blank on
  the doctor (empty list = ready to register). Used as a pre-flight so we never
  send a request Medikit will 400, and so the backfill can report *why* a doctor
  was skipped.
  """
  def missing_register_fields(%{} = doctor) do
    [
      {:first_name, doctor.first_name},
      {:paternal_surname, doctor.paternal_surname},
      {:maternal_surname, doctor.maternal_surname},
      {:cedula_profesional, doctor.cedula_profesional},
      {:birthdate, doctor.birthdate},
      {:phone, doctor.phone},
      {:email, doctor.email},
      {:university, doctor.university},
      {:medikit_specialty_id, doctor.medikit_specialty_id},
      {:address_state, doctor.address_state},
      {:address_city, doctor.address_city},
      {:address_line, doctor.address_line},
      {:address_zipcode, doctor.address_zipcode}
    ]
    |> Enum.filter(fn {_k, v} -> blank?(v) end)
    |> Enum.map(&elem(&1, 0))
  end

  # ── /doctors request body (doctors-1.0.38 getDoctorRequestType) ──────────
  defp register_body(doctor, cfg) do
    drop_blank(%{
      # account-scoped
      "Payer" => cfg[:payer],
      "OrganizationId" => cfg[:organization_id],
      "PurchaserPlan" => cfg[:purchaser_plan],
      "SourceSystem" => cfg[:source_system],
      "SourceSystemIdentifier" => doctor.id,
      # identity
      "FirstName" => doctor.first_name,
      "LastName" => last_name(doctor),
      "Birthdate" => format_birthdate(doctor.birthdate),
      "Gender" => doctor.gender,
      "Phone" => format_phone(doctor.phone),
      "Mobile" => format_phone(doctor.phone),
      "Email" => doctor.email,
      "ProfessionalLicense" => doctor.cedula_profesional,
      "SpecialtyId" => doctor.medikit_specialty_id,
      "Institution" => doctor.university,
      "TaxId" => doctor.tax_id,
      # address (Country per-doctor, falling back to the config default / MX)
      "Country" => doctor.address_country || cfg[:country] || "MX",
      "State" => doctor.address_state,
      "City" => doctor.address_city,
      "Address" => doctor.address_line,
      "Zipcode" => doctor.address_zipcode
    })
  end

  # Medikit register LastName = both apellidos.
  defp last_name(%{paternal_surname: p, maternal_surname: m}) do
    [p, m] |> Enum.reject(&blank?/1) |> Enum.join(" ")
  end

  # RAML Birthdate format: "YYYY-MM-DD HH:MM:SS".
  defp format_birthdate(%Date{} = d), do: Date.to_iso8601(d) <> " 00:00:00"
  defp format_birthdate(_), do: nil

  # RAML phone pattern is +[country][number]. Our phones are stored digits-only
  # (Doctor.normalize_phone strips non-digits), so prefix "+".
  defp format_phone(nil), do: nil
  defp format_phone("+" <> _ = p), do: p

  defp format_phone(phone) when is_binary(phone) do
    case String.replace(phone, ~r/[^0-9]/, "") do
      "" -> nil
      digits -> "+" <> digits
    end
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false

  defp headers(api_key), do: [{"api-key", api_key}]

  defp drop_blank(map) do
    map
    |> Enum.reject(fn {_k, v} -> blank?(v) end)
    |> Map.new()
  end

  # Reads + validates the :medikit config. Returns {:ok, base_url, api_key, cfg}
  # or an error tuple.
  defp config do
    cfg = Application.get_env(:ledgr, :medikit, [])

    cond do
      cfg[:enabled] == false -> {:error, :disabled}
      blank?(cfg[:base_url]) -> {:error, :missing_base_url}
      blank?(cfg[:api_key]) -> {:error, :missing_api_key}
      true -> {:ok, String.trim_trailing(cfg[:base_url], "/"), cfg[:api_key], cfg}
    end
  end

  defp blank?(nil), do: true
  defp blank?(v) when is_binary(v), do: String.trim(v) == ""
  defp blank?(_), do: false

  # Injects a Req.Test plug in test env via application config (mirrors Prescrypto).
  defp test_plug_opts do
    case Application.get_env(:ledgr, :medikit_test_plug) do
      nil -> []
      plug -> [plug: plug]
    end
  end
end
