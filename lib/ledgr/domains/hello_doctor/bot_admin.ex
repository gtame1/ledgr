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
    * `:notes` — free text rationale
    * `:marked_by` — operator handle

  Bot ADR-059 structured fields (omit = unchanged, `""` = clear):

    * `:failure_category` — value from `ConversationFeedback.failure_categories/0`
    * `:first_bad_message_id` / `:exemplary_message_id` — message anchors
    * `:corrected_response` — what the bot should have said
  """
  def mark_conversation(conv_id, attrs) when is_binary(conv_id) and is_map(attrs) do
    case config() do
      {:ok, base_url, api_key} ->
        url = base_url <> "/admin/conversations/" <> conv_id <> "/quality"

        body =
          Map.take(attrs, [
            :signal,
            :corpus_candidate,
            :notes,
            :marked_by,
            :failure_category,
            :first_bad_message_id,
            :exemplary_message_id,
            :corrected_response
          ])

        request(:post, url, body, [], api_key)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Sets or clears the live operator case note on a conversation (bot
  ADR-059). The bot injects it into the LLM context on every later turn
  of that conversation. `notes` nil/blank clears; the bot caps length
  at 1500 chars (422 beyond it).
  """
  def set_operator_notes(conv_id, notes, updated_by)
      when is_binary(conv_id) and is_binary(updated_by) do
    case config() do
      {:ok, base_url, api_key} ->
        url = base_url <> "/admin/conversations/" <> conv_id <> "/operator-notes"

        request(:put, url, %{notes: notes, updated_by: updated_by}, [], api_key)

      {:error, _} = err ->
        err
    end
  end

  # ── Corporate accounts (ADR-046) ────────────────────────────────

  @doc "Lists all corporate accounts. Returns `{count, accounts: [...]}` on success."
  def list_corporate_accounts do
    case config() do
      {:ok, base, key} -> request(:get, base <> "/admin/corporate", [], [], key)
      {:error, _} = err -> err
    end
  end

  @doc "Fetches a single corporate account by slug."
  def get_corporate_account(slug) when is_binary(slug) do
    case config() do
      {:ok, base, key} -> request(:get, base <> "/admin/corporate/" <> slug, [], [], key)
      {:error, _} = err -> err
    end
  end

  @doc """
  Creates a corporate account.
  `attrs` keys: `:slug` (required), `:name` (required), `:consultation_rate_mxn` (optional).
  """
  def create_corporate_account(attrs) when is_map(attrs) do
    body = Map.take(attrs, [:slug, :name, :consultation_rate_mxn])

    case config() do
      {:ok, base, key} -> request(:post, base <> "/admin/corporate", body, [], key)
      {:error, _} = err -> err
    end
  end

  @doc """
  Patches an existing account. `attrs` keys: any of `:name`, `:status`,
  `:consultation_rate_mxn`. At least one must be present.
  """
  def update_corporate_account(slug, attrs) when is_binary(slug) and is_map(attrs) do
    body = Map.take(attrs, [:name, :status, :consultation_rate_mxn])

    case config() do
      {:ok, base, key} ->
        request(:patch, base <> "/admin/corporate/" <> slug, body, [], key)

      {:error, _} = err ->
        err
    end
  end

  @doc "Lists members for a slug; pass `include_removed: true` to include soft-deleted."
  def list_corporate_members(slug, opts \\ []) when is_binary(slug) do
    case config() do
      {:ok, base, key} ->
        params =
          case Keyword.get(opts, :include_removed) do
            true -> [{"include_removed", "true"}]
            _ -> []
          end

        request(:get, base <> "/admin/corporate/" <> slug <> "/members", [], params, key)

      {:error, _} = err ->
        err
    end
  end

  @doc "Bulk-adds members to a slug. `phones` is a list of strings (any format)."
  def add_corporate_members(slug, phones) when is_binary(slug) and is_list(phones) do
    case config() do
      {:ok, base, key} ->
        request(
          :post,
          base <> "/admin/corporate/" <> slug <> "/members",
          %{phones: phones},
          [],
          key
        )

      {:error, _} = err ->
        err
    end
  end

  @doc "Removes (soft-deletes) one member by phone."
  def remove_corporate_member(slug, phone) when is_binary(slug) and is_binary(phone) do
    case config() do
      {:ok, base, key} ->
        request(
          :delete,
          base <> "/admin/corporate/" <> slug <> "/members/" <> URI.encode(phone),
          [],
          [],
          key
        )

      {:error, _} = err ->
        err
    end
  end

  @doc "Fetches a monthly invoice preview for a slug. `month` is `YYYY-MM`."
  def get_corporate_invoice(slug, month) when is_binary(slug) and is_binary(month) do
    case config() do
      {:ok, base, key} ->
        request(
          :get,
          base <> "/admin/corporate/" <> slug <> "/invoice",
          [],
          [{"month", month}],
          key
        )

      {:error, _} = err ->
        err
    end
  end

  # ── Doctor news blast (one-shot announcement) ───────────────────

  @doc """
  Sends a one-shot news/announcement to doctors via the bot's pre-approved
  WhatsApp template.

  `message` is the operator's body text only — the bot wraps it with a fixed
  greeting (`Hola Dr. {nombre}, te compartimos una novedad de Hello Doctor:`)
  and signature (`— Equipo Hello Doctor`). It must be 1–1000 chars after
  trimming (the bot rejects empty/oversized with HTTP 400).

  `filters` narrows the recipient set; all keys optional and AND-ed together
  (omitted/false = no narrowing → every doctor):

    * `:specialty` — case-insensitive substring match on specialty
    * `:available_only` — only doctors marked available
    * `:terms_accepted_only` — only doctors who accepted T&C
    * `:direct_only` — only "Direct" doctors (those with a consultation fee)
    * `:exclude_deactivated` — skip offboarded/deactivated doctors
    * `:doctor_ids` — explicit list of doctor IDs (hand-picked recipients).
      When present, the caller should send *only* this and omit the attribute
      filters so the selection is unambiguous.

  `dry_run: true` previews recipients (redacted, last-4-only) and sends
  nothing; `false` performs the real, irreversible blast.

  Unlike the other helpers here, this returns the raw HTTP status so callers
  can map the bot's contract precisely (400 = bad message, 401/422 = key
  misconfig):

    * `{:ok, status, body}` — the call completed (any status; body is decoded)
    * `{:error, :config, reason}` — bot URL / admin key not configured
    * `{:error, :network, reason}` — connection failure / timeout
  """
  def broadcast_doctor_news(message, filters \\ %{}, dry_run \\ false)
      when is_binary(message) and is_map(filters) and is_boolean(dry_run) do
    case config() do
      {:ok, base, key} ->
        body =
          filters
          |> Map.take([
            :specialty,
            :available_only,
            :terms_accepted_only,
            :direct_only,
            :exclude_deactivated,
            :doctor_ids
          ])
          |> Map.put(:message, message)
          |> Map.put(:dry_run, dry_run)

        request_with_status(:post, base <> "/admin/doctors/broadcast-news", body, key)

      {:error, reason} ->
        {:error, :config, reason}
    end
  end

  @doc """
  Lists the full doctor roster from the bot's admin API. Used to populate the
  hand-pick recipient checklist on the news blast screen.

  Returns `{:ok, [doctor_map, ...]}` where each map has string keys including
  `"id"` (the selection key for `:doctor_ids`), `"name"`, `"specialty"`, and
  status flags. NOTE: this endpoint returns **full phone numbers** — callers
  proxying to the browser must strip `"phone"` first.
  """
  def list_doctors do
    case config() do
      {:ok, base, key} -> request(:get, base <> "/admin/doctors", [], [], key)
      {:error, _} = err -> err
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
        Logger.warning("[HelloDoctor BotAdmin] #{method} #{url} failed: #{inspect(exception)}")

        {:error, "network error: #{Exception.message(exception)}"}
    end
  end

  # Like request/5 but surfaces the raw HTTP status to the caller instead of
  # collapsing non-2xx into an opaque {:error, string}. Used by the doctor news
  # blast proxy, which mirrors the bot's status/body straight back to the
  # browser so the UI can branch on 400 vs 401/422.
  defp request_with_status(method, url, body, api_key) do
    opts = [
      method: method,
      url: url,
      headers: [{"x-api-key", api_key}],
      json: body,
      receive_timeout: @timeout,
      connect_options: [timeout: @timeout]
    ]

    case Req.request(opts) do
      {:ok, %Req.Response{status: status, body: resp_body}} ->
        if status not in 200..299 do
          Logger.warning(
            "[HelloDoctor BotAdmin] #{method} #{url} returned #{status}: #{inspect(resp_body)}"
          )
        end

        {:ok, status, resp_body}

      {:error, exception} ->
        Logger.warning("[HelloDoctor BotAdmin] #{method} #{url} failed: #{inspect(exception)}")

        {:error, :network, Exception.message(exception)}
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
