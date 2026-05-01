defmodule Ledgr.Domains.AumentaMiPension.BotApi do
  @moduledoc """
  HTTP client for the AMP bot service's admin endpoints.

  Currently exposes only customer reset. The bot service (FastAPI on AWS App
  Runner) is the source of truth for conversation/message/customer state, so
  destructive operations on those tables go through the bot rather than
  Ledgr touching upstream tables directly. See
  `Ledgr.Domains.AumentaMiPension.CustomerReset` for the caller.

  ## Configuration

      config :ledgr,
        aumenta_mi_pension_bot_url: "https://bwt6kpsvip.us-east-1.awsapprunner.com",
        aumenta_mi_pension_bot_admin_api_key: "..."
  """

  require Logger

  @doc """
  Resets a customer on the bot side.

  Options:
    * `:dry_run` (boolean, default false) — preview only, no mutations
    * `:force` (boolean, default false) — override unfulfilled-payment guard
    * `:reset_terms` (boolean, default false) — also clear terms-of-service
      acceptance (for LFPDPPP / right-to-erasure requests)
    * `:reason` (string) — surfaced in bot logs for audit

  Returns:
    * `{:ok, response_body}` — bot returned 200 with the result map
    * `{:error, {:unfulfilled_payments, pending}}` — bot returned 409;
      `pending` is the list of obligations blocking the reset
    * `{:error, {:not_configured, which}}` — URL or API key missing in config
    * `{:error, {:http_error, status, body}}` — any other non-2xx response
    * `{:error, reason}` — transport or unexpected error
  """
  def reset_customer(phone, opts \\ []) do
    with {:ok, base_url} <- fetch_config(:aumenta_mi_pension_bot_url, :url),
         {:ok, api_key} <- fetch_config(:aumenta_mi_pension_bot_admin_api_key, :api_key) do
      body = %{
        dry_run: Keyword.get(opts, :dry_run, false),
        force: Keyword.get(opts, :force, false),
        reset_terms: Keyword.get(opts, :reset_terms, false),
        reason: Keyword.get(opts, :reason, "ledgr admin")
      }

      url = String.trim_trailing(base_url, "/") <> "/admin/customers/#{phone}/reset"

      Logger.info(
        "[AumentaMiPension BotApi] POST reset phone=#{phone} dry_run=#{body.dry_run} force=#{body.force}"
      )

      case Req.post(url,
             headers: [{"x-api-key", api_key}, {"content-type", "application/json"}],
             json: body,
             receive_timeout: 30_000
           ) do
        {:ok, %{status: 200, body: response_body}} ->
          {:ok, response_body}

        {:ok, %{status: 409, body: %{"detail" => %{"error" => "unfulfilled_payments"} = detail}}} ->
          {:error, {:unfulfilled_payments, Map.get(detail, "pending", [])}}

        {:ok, %{status: status, body: body}} ->
          Logger.warning(
            "[AumentaMiPension BotApi] reset returned HTTP #{status}: #{inspect(body)}"
          )

          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.error("[AumentaMiPension BotApi] reset transport error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp fetch_config(key, label) do
    case Application.get_env(:ledgr, key) do
      nil -> {:error, {:not_configured, label}}
      "" -> {:error, {:not_configured, label}}
      value -> {:ok, value}
    end
  end
end
