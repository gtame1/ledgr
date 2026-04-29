defmodule Ledgr.Domains.HelloDoctor.Prescrypto do
  require Logger

  @doc """
  Registers a doctor with Prescrypto and returns {:ok, %{prescrypto_medic_id: int, prescrypto_token: string}}
  or {:error, reason}. Never logs or exposes the token in error messages.
  """
  def create_medic(%{email: nil}), do: {:error, :missing_email}
  def create_medic(%{cedula_profesional: nil}), do: {:error, :missing_cedula}

  def create_medic(doctor) do
    config = Application.get_env(:ledgr, :prescrypto, [])

    if config[:enabled] == false do
      {:error, :disabled}
    else
      base_url = config[:base_url] || "https://integration.prescrypto.com/"
      token = config[:token]

      body = %{
        "name" => doctor.name,
        "email" => doctor.email,
        "password" => random_password(),
        "cedula_prof" => doctor.cedula_profesional,
        "specialty" => doctor.specialty,
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
        {:ok, %{status: 201, body: resp_body}} ->
          {:ok, %{prescrypto_medic_id: resp_body["id"], prescrypto_token: resp_body["token"]}}

        {:ok, %{status: status, body: resp_body}} when status in 400..499 ->
          Logger.warning(
            "[Prescrypto] create_medic failed for doctor #{doctor.id}: status=#{status} errors=#{inspect(resp_body)}"
          )

          {:error, {:api_error, status, resp_body}}

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
