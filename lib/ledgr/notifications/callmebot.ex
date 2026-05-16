defmodule Ledgr.Notifications.CallMeBot do
  @moduledoc """
  Thin HTTP client for sending WhatsApp messages via the free CallMeBot API.

  ## One-time setup

  From the receiving phone, send the literal text
  `I allow callmebot to send me messages` to `+34 644 51 96 80`. CallMeBot
  replies with an API key. Put that key in `CALLMEBOT_API_KEY`.

  ## Configuration

      config :ledgr, :callmebot,
        api_key: System.get_env("CALLMEBOT_API_KEY")

  If the key is missing, `send_text/2` returns `{:error, :not_configured}`
  and logs a warning. Callers should treat this as a soft failure —
  alerts are non-critical.

  ## Limits

  - Free tier only sends to the phone that authorized the API key.
  - Rate-limited (a few messages per minute) by CallMeBot.
  """

  require Logger

  @api_url "https://api.callmebot.com/whatsapp.php"
  @timeout_ms 10_000

  @doc """
  Sends a text WhatsApp message to `phone`.

  `phone` should be E.164 with or without the leading `+`; this module
  normalizes to the form CallMeBot expects (`+E164`).

  Returns `{:ok, body}` on success, `{:error, reason}` otherwise. Does
  not raise — outages must not break the calling flow.
  """
  def send_text(phone, message) when is_binary(phone) and is_binary(message) do
    with {:ok, api_key} <- fetch_api_key() do
      normalized_phone = normalize_phone(phone)

      Logger.info(
        "[CallMeBot] sending message to #{normalized_phone} (#{byte_size(message)} bytes)"
      )

      case Req.get(@api_url,
             params: [
               phone: normalized_phone,
               text: message,
               apikey: api_key
             ],
             receive_timeout: @timeout_ms
           ) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          {:ok, body}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("[CallMeBot] send returned HTTP #{status}: #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.error("[CallMeBot] send transport error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Same as `send_text/2` but runs in an unsupervised task so the caller
  never blocks. Returns `:ok` immediately; errors are logged inside
  `send_text/2`.
  """
  def send_text_async(phone, message) when is_binary(phone) and is_binary(message) do
    Task.start(fn -> send_text(phone, message) end)
    :ok
  end

  # ── Private ──────────────────────────────────────────────────────────

  defp fetch_api_key do
    config = Application.get_env(:ledgr, :callmebot, [])

    case Keyword.get(config, :api_key) do
      nil ->
        Logger.warning("[CallMeBot] missing CALLMEBOT_API_KEY — skipping send")
        {:error, :not_configured}

      "" ->
        Logger.warning("[CallMeBot] empty CALLMEBOT_API_KEY — skipping send")
        {:error, :not_configured}

      value ->
        {:ok, value}
    end
  end

  defp normalize_phone("+" <> _ = phone), do: phone
  defp normalize_phone(phone) when is_binary(phone), do: "+" <> phone
end
