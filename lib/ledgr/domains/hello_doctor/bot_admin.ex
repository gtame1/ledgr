defmodule Ledgr.Domains.HelloDoctor.BotAdmin do
  @moduledoc """
  HTTP client for the HelloDoctor bot's `/admin/conversations` endpoints.

  The bot exposes quality-marking APIs that let operators tag conversations
  as good/bad/corpus-candidate so a separate harvest script can pull
  training material from labelled corpus rows. This module wraps the
  read + mark calls so the Ledgr Triage page can drive them without
  curling.

  Configured via env vars (see runtime.exs):

    * `HELLO_DOCTOR_BOT_URL` — base URL, e.g. `https://bot.example.com`
    * `HELLO_DOCTOR_BOT_ADMIN_API_KEY` — sent as `X-API-Key`

  All functions return `{:ok, body}` on 2xx or `{:error, reason}` for
  anything else (network failure, non-2xx, missing config). The body for
  successful list calls is a list of conversation maps with string keys.
  """

  require Logger

  @timeout 10_000

  @doc """
  Lists conversations from the bot's admin API.

  ## Options (all optional)

    * `:signal` — `"good"` / `"bad"` / `"unmarked"` (auto-hint mode)
    * `:auto_hint` — one of the bot's auto_hint values; or pass the auto_hint
      directly as `:signal` (the bot accepts both `signal=unmarked` and
      `signal=likely_bad`)
    * `:tenant` — e.g. `"direct"`
    * `:corpus_candidate` — boolean
    * `:limit` — integer
  """
  def list_conversations(opts \\ []) do
    case config() do
      {:ok, base_url, api_key} ->
        params =
          opts
          |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
          |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

        url = base_url <> "/admin/conversations"

        request(:get, url, [], params, api_key)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Marks a conversation's quality state.

  `attrs` map keys (all optional but at least one must be present):

    * `:signal` — `"good"` / `"bad"` (omit to leave unchanged)
    * `:corpus_candidate` — boolean
    * `:notes` — free text
    * `:marked_by` — operator handle
  """
  def mark_conversation(conv_id, attrs) when is_binary(conv_id) and is_map(attrs) do
    case config() do
      {:ok, base_url, api_key} ->
        url = base_url <> "/admin/conversations/" <> conv_id <> "/quality"

        body = Map.take(attrs, [:signal, :corpus_candidate, :notes, :marked_by])

        request(:post, url, body, [], api_key)

      {:error, _} = err ->
        err
    end
  end

  # ── Internal ────────────────────────────────────────────────────

  defp config do
    base_url = Application.get_env(:ledgr, :hello_doctor_bot_url)
    api_key = Application.get_env(:ledgr, :hello_doctor_bot_admin_api_key)

    cond do
      is_nil(base_url) or base_url == "" ->
        {:error, "HELLO_DOCTOR_BOT_URL not configured"}

      is_nil(api_key) or api_key == "" ->
        {:error, "HELLO_DOCTOR_BOT_ADMIN_API_KEY not configured"}

      true ->
        {:ok, String.trim_trailing(base_url, "/"), api_key}
    end
  end

  defp request(method, url, body, params, api_key) do
    headers = [{"x-api-key", api_key}]

    opts = [
      method: method,
      url: url,
      headers: headers,
      params: params,
      receive_timeout: @timeout,
      connect_options: [timeout: @timeout]
    ]

    opts = if body == [] or body == %{}, do: opts, else: Keyword.put(opts, :json, body)

    case Req.request(opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning(
          "[HelloDoctor BotAdmin] #{method} #{url} returned #{status}: #{inspect(body)}"
        )

        {:error, "bot returned HTTP #{status}: #{summarize_error_body(body)}"}

      {:error, exception} ->
        Logger.warning(
          "[HelloDoctor BotAdmin] #{method} #{url} failed: #{inspect(exception)}"
        )

        {:error, "network error: #{Exception.message(exception)}"}
    end
  end

  # Pulls a human-readable validation message out of the bot's error body.
  # FastAPI-style bodies look like %{"detail" => [%{"loc" => [...], "msg" => ...}]}
  # or %{"detail" => "message"}; fall back to a truncated inspect otherwise.
  defp summarize_error_body(%{"detail" => detail}) when is_binary(detail), do: detail

  defp summarize_error_body(%{"detail" => items}) when is_list(items) do
    items
    |> Enum.map(fn
      %{"loc" => loc, "msg" => msg} -> "#{Enum.join(List.wrap(loc), ".")}: #{msg}"
      %{"msg" => msg} -> msg
      other -> inspect(other)
    end)
    |> Enum.join("; ")
    |> String.slice(0, 300)
  end

  defp summarize_error_body(body) when is_binary(body), do: String.slice(body, 0, 300)
  defp summarize_error_body(body), do: body |> inspect() |> String.slice(0, 300)
end
