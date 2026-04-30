defmodule Ledgr.Domains.HelloDoctor.Prescrypto do
  require Logger

  @doc """
  Registers a doctor with Prescrypto and returns {:ok, %{prescrypto_medic_id: int, prescrypto_token: string}}
  or {:error, reason}. Never logs or exposes the token in error messages.
  """
  def create_medic(%{email: nil}), do: {:error, :missing_email}
  def create_medic(%{cedula_profesional: nil}), do: {:error, :missing_cedula}
  def create_medic(%{prescrypto_specialty_no: nil}), do: {:error, :missing_specialty_no}

  def create_medic(doctor) do
    alias Ledgr.Domains.HelloDoctor.Specialties

    config = Application.get_env(:ledgr, :prescrypto, [])

    if config[:enabled] == false do
      {:error, :disabled}
    else
      base_url = config[:base_url] || "https://integration.prescrypto.com/"
      token = config[:token]

      prescrypto_specialty_id = Specialties.prescrypto_specialty_id_for(doctor.specialty)

      body = %{
        "name" => doctor.name,
        "email" => doctor.email,
        "password" => random_password(),
        "cedula_prof" => doctor.cedula_profesional,
        "specialty" => prescrypto_specialty_id || doctor.specialty,
        "specialty_no" => doctor.prescrypto_specialty_no,
        "alma_mater" => doctor.university
      }

      req_opts =
        [
          url: "/api/v2/medics/",
          json: body,
          headers: [{"authorization", "Token #{token}"}]
        ] ++ test_plug_opts()

      case Req.post(Req.new(base_url: base_url), req_opts) do
        {:ok, %{status: status, body: resp_body}} when status in [200, 201] ->
          {:ok, %{prescrypto_medic_id: resp_body["id"], prescrypto_token: resp_body["token"]}}

        {:ok, %{status: status, body: resp_body}} when status in 400..499 ->
          if duplicate_email_error?(resp_body) do
            # Doctor already registered — look them up by email instead
            Logger.info("[Prescrypto] Doctor #{doctor.id} already exists, fetching by email")
            find_existing_medic(doctor.email, base_url, token)
          else
            Logger.warning(
              "[Prescrypto] create_medic failed for doctor #{doctor.id}: status=#{status} errors=#{inspect(resp_body)}"
            )

            {:error, {:api_error, status, resp_body}}
          end

        {:ok, %{status: status}} ->
          Logger.warning(
            "[Prescrypto] create_medic unexpected status=#{status} for doctor #{doctor.id}"
          )

          {:error, {:unexpected_status, status}}

        {:error, reason} ->
          Logger.warning(
            "[Prescrypto] create_medic HTTP error for doctor #{doctor.id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  @doc """
  Fetches the full Prescrypto specialty catalog (all pages).
  Returns {:ok, [%{id: integer, name: string}]} or {:error, reason}.
  """
  def fetch_all_specialties do
    config = Application.get_env(:ledgr, :prescrypto, [])
    base_url = config[:base_url] || "https://integration.prescrypto.com/"
    token = config[:token]

    if is_nil(token) do
      {:error, :no_api_key}
    else
      fetch_specialties_page(base_url, token, "/api/v2/specialities/?limit=150", [])
    end
  end

  defp fetch_specialties_page(_base_url, _token, nil, acc), do: {:ok, Enum.reverse(acc)}

  defp fetch_specialties_page(base_url, token, path_or_url, acc) do
    # Handle both relative paths and absolute next-page URLs from Prescrypto
    url =
      if String.starts_with?(path_or_url, "http"),
        do: path_or_url,
        else: base_url <> String.trim_leading(path_or_url, "/")

    case Req.get(Req.new(), url: url, headers: [{"authorization", "Token #{token}"}]) do
      {:ok, %{status: 200, body: %{"results" => results, "next" => next}}} ->
        items = Enum.map(results, &%{id: &1["id"], name: &1["name"]})
        fetch_specialties_page(base_url, token, next, Enum.reverse(items) ++ acc)

      {:ok, %{status: status}} ->
        Logger.warning("[Prescrypto] fetch_all_specialties unexpected status=#{status}")
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.warning("[Prescrypto] fetch_all_specialties error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Returns true when the Prescrypto error body indicates the email is already taken.
  defp duplicate_email_error?(body) when is_list(body) do
    Enum.any?(body, fn msg ->
      is_binary(msg) && String.contains?(msg, "email") &&
        String.contains?(msg, "duplicate key value")
    end)
  end

  defp duplicate_email_error?(_), do: false

  # Fetches an existing Prescrypto medic by email. Token is not available via GET,
  # so it is returned as nil — the medic ID is sufficient for prescription linking.
  defp find_existing_medic(email, base_url, token) do
    url = base_url <> "api/v2/medics/?email=#{URI.encode_www_form(email)}"

    case Req.get(Req.new(), url: url, headers: [{"authorization", "Token #{token}"}]) do
      {:ok, %{status: 200, body: %{"results" => [medic | _]}}} ->
        {:ok, %{prescrypto_medic_id: medic["id"], prescrypto_token: nil}}

      {:ok, %{status: 200, body: %{"results" => []}}} ->
        Logger.warning("[Prescrypto] Duplicate email but medic not found by lookup for #{email}")
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp random_password do
    :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
  end

  # Injects Req.Test plug in test env via application config
  defp test_plug_opts do
    case Application.get_env(:ledgr, :prescrypto_test_plug) do
      nil -> []
      plug -> [plug: plug]
    end
  end
end
