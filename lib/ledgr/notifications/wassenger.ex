defmodule Ledgr.Notifications.Wassenger do
  @moduledoc """
  Thin HTTP client for sending WhatsApp messages via the Wassenger API.

  ## Configuration

      config :ledgr, :wassenger,
        api_key: System.get_env("WASSENGER_API_KEY"),
        device_id: System.get_env("WASSENGER_DEVICE_ID")

  Both values are required to send. If either is missing the module logs
  a warning and returns `{:error, :not_configured}` — callers should treat
  this as a soft failure (alerts are non-critical).

  ## Usage

      Wassenger.send_text("525543417149", "New order #123!")

  Phone numbers are E.164 without the leading `+`.
  """

  require Logger

  @api_base "https://api.wassenger.com/v1"
  @send_timeout_ms 10_000

  @doc """
  Sends a text WhatsApp message to `phone` (E.164 without leading `+`).

  Returns `{:ok, body}` on success, `{:error, reason}` otherwise. Does
  not raise — Wassenger outages must not break the calling flow.
  """
  def send_text(phone, message) when is_binary(phone) and is_binary(message) do
    with {:ok, api_key} <- fetch_config(:api_key),
         {:ok, device_id} <- fetch_config(:device_id) do
      body = %{
        phone: phone,
        message: message,
        device: device_id
      }

      Logger.info("[Wassenger] sending message to #{phone} (#{byte_size(message)} bytes)")

      case Req.post(@api_base <> "/messages",
             headers: [
               {"token", api_key},
               {"content-type", "application/json"}
             ],
             json: body,
             receive_timeout: @send_timeout_ms
           ) do
        {:ok, %{status: status, body: resp}} when status in 200..299 ->
          {:ok, resp}

        {:ok, %{status: status, body: resp}} ->
          Logger.warning("[Wassenger] send returned HTTP #{status}: #{inspect(resp)}")
          {:error, {:http_error, status, resp}}

        {:error, reason} ->
          Logger.error("[Wassenger] send transport error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Same as `send_text/2` but runs in an unsupervised task so the caller
  never blocks. Returns `:ok` immediately. Errors are logged inside
  `send_text/2`.
  """
  def send_text_async(phone, message) when is_binary(phone) and is_binary(message) do
    Task.start(fn -> send_text(phone, message) end)
    :ok
  end

  defp fetch_config(key) do
    config = Application.get_env(:ledgr, :wassenger, [])

    case Keyword.get(config, key) do
      nil ->
        Logger.warning("[Wassenger] missing config #{inspect(key)} — skipping send")
        {:error, :not_configured}

      "" ->
        Logger.warning("[Wassenger] empty config #{inspect(key)} — skipping send")
        {:error, :not_configured}

      value ->
        {:ok, value}
    end
  end
end
