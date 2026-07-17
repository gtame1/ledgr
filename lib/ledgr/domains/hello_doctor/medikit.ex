defmodule Ledgr.Domains.HelloDoctor.Medikit do
  @moduledoc """
  Client for Medikit's doctors API (doctors-1.0.38 RAML), used to migrate
  Hello Doctor off Prescrypto for digital prescriptions.

  Auth is a single account-level `API-KEY` header (not per-doctor). All calls go
  to the configured `base_url`. Config from
  `Application.get_env(:ledgr, :medikit)`:

      base_url        — doctors host. PROD (the org hello-doctor's key talks to):
                        https://medikit-doctors-0z7bqo.5sc6y6-2.usa-e2.cloudhub.io/api
                        UAT (testing only): https://api-doctors-1jqz1q.5sc6y6-2.usa-e2.cloudhub.io/api
      api_key         — account API-KEY header value. MUST be the same account
                        key hello-doctor prod uses (SSM
                        /hello-doctor/prod/MEDIKIT_API_KEY) — key selects the
                        Salesforce org, and hello-doctor consumes the ids we mint.
                        Org tell: PROD HealthcareProvider ids start "0cmVK";
                        "0cmE2" means UAT/another org, and hello-doctor's
                        POST /prescription then 400s with
                        "No se registro encuentro clinico" (2026-07-17 incident:
                        12/14 doctors re-registered by hand).
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

  # Medikit's backend is a Salesforce org, and it maps our address fields onto
  # standard Salesforce Shipping* address fields, which have hard length caps.
  # Long Mexican municipality names blow past the City cap (e.g. "Dolores
  # Hidalgo Cuna de la Independencia Nacional", 49 chars) and fail the WHOLE
  # register with STRING_TOO_LONG — so we clamp each address field to its
  # Salesforce max before sending. City is the tight one at 40.
  @sf_city_max 40
  @sf_state_max 80
  @sf_street_max 255
  @sf_zipcode_max 20

  # The UAT cédula validator (SEP upstream) can hang ~30s before answering, well
  # past Finch's 15s default → a `Req.TransportError{reason: :timeout}`. Give
  # both calls headroom so a slow-but-valid response isn't killed.
  @receive_timeout 45_000

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
  When true, provisioning skips the `validate-professional-license` step and
  registers directly. An escape hatch for when the SEP cédula validator (an
  external upstream) is down/degraded — it hangs ~30s then 503s, blocking all
  provisioning even though `POST /doctors` itself works. Set via
  `MEDIKIT_SKIP_LICENSE_VALIDATION=true`. Off by default; turn it back off once
  SEP is healthy so the cédula check resumes as a hard gate. Registering an
  unvalidated cédula is on the operator who flips this.
  """
  def skip_license_validation? do
    Application.get_env(:ledgr, :medikit, [])[:skip_license_validation] == true
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
        [
          url: @validate_path,
          json: body,
          headers: headers(api_key),
          receive_timeout: @receive_timeout
        ] ++ test_plug_opts()

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
        [
          url: @register_path,
          json: register_body(doctor, cfg),
          headers: headers(api_key),
          receive_timeout: @receive_timeout
        ] ++ test_plug_opts()

      case Req.post(Req.new(base_url: base_url), req_opts) do
        {:ok, %{status: 200, body: body}} = response ->
          # RAML envelope is {"Status":"OK","Data":"<id>"} but the live UAT
          # host has been observed returning lowercase keys — tolerate both.
          case {response_status(body), response_data(body)} do
            {"OK", id} when is_binary(id) and id != "" ->
              {:ok, id}

            _ ->
              # 200 with Status:"Error" (Data carries the message) or an
              # unexpected shape — fail-closed.
              reject(doctor, response)
          end

        {:ok, %{status: status}} = response when status != 200 ->
          # Non-200 (e.g. 400) — Data carries the message.
          reject(doctor, response)

        {:error, reason} ->
          Logger.warning("[Medikit] register_doctor #{doctor.id} HTTP error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp reject(doctor, {:ok, %{status: status, body: resp}}) do
    Logger.warning(
      "[Medikit] register_doctor #{doctor.id} rejected status=#{status} body=#{inspect(resp)}"
    )

    {:error, {:rejected, status, resp}}
  end

  # Envelope key casing varies between the RAML spec ("Status"/"Data") and the
  # live UAT host ("status"/"data") — read either.
  defp response_status(%{"Status" => s}), do: s
  defp response_status(%{"status" => s}), do: s
  defp response_status(_), do: nil

  defp response_data(%{"Data" => d}), do: d
  defp response_data(%{"data" => d}), do: d
  defp response_data(_), do: nil

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
      # address (Country per-doctor, falling back to the config default / MX).
      # Each field clamped to its Salesforce Shipping* max — see @sf_*_max.
      "Country" => doctor.address_country || cfg[:country] || "MX",
      "State" => clamp(doctor.address_state, @sf_state_max, "State"),
      "City" => clamp(doctor.address_city, @sf_city_max, "City"),
      "Address" => clamp(doctor.address_line, @sf_street_max, "Address"),
      "Zipcode" => clamp(doctor.address_zipcode, @sf_zipcode_max, "Zipcode")
    })
  end

  # Clamp a string to Salesforce's field-length cap, preferring a clean cut at
  # a word boundary so a truncated city stays readable ("Dolores Hidalgo Cuna
  # de la Independencia Nacional" → "Dolores Hidalgo Cuna de la Independencia").
  # Logs whenever it trims, so a silently-shortened address is still visible.
  defp clamp(nil, _max, _label), do: nil

  defp clamp(v, max, label) when is_binary(v) do
    if String.length(v) <= max do
      v
    else
      truncated = word_truncate(v, max)

      Logger.info(
        "[Medikit] clamped #{label} to Salesforce max #{max}: " <>
          "#{inspect(v)} -> #{inspect(truncated)}"
      )

      truncated
    end
  end

  defp word_truncate(v, max) do
    sliced = String.slice(v, 0, max)

    # If the cut fell mid-word, back off to the last whitespace; if there's no
    # earlier space (a single over-long token), keep the hard character cut.
    if String.at(v, max) == " " do
      String.trim_trailing(sliced)
    else
      case Regex.run(~r/^(.*)\s\S+$/u, sliced) do
        [_, head] when head != "" -> String.trim_trailing(head)
        _ -> sliced
      end
    end
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
