defmodule Ledgr.Domains.HelloDoctor.BillingSync do
  @moduledoc """
  Pulls external service billing data and stores it in the `external_costs` table.

  Services:
  - OpenAI: usage completions + embeddings API, priced locally by token counts
  - Whereby: meeting list API, priced by duration (estimated)
  - Evolution API (Zenzeia): no billing endpoint — always returns {:ok, :not_supported}
  - AWS App Runner: Cost Explorer API with manual SigV4 signing

  ## Configuration (runtime.exs / env vars)

  - `HELLO_DOCTOR_OPENAI_API_KEY`     — OpenAI admin key (sk-admin-... or org-level key)
  - `HELLO_DOCTOR_WHEREBY_API_KEY`    — Whereby JWT token
  - `HELLO_DOCTOR_AWS_ACCESS_KEY_ID`  — IAM key with ce:GetCostAndUsage
  - `HELLO_DOCTOR_AWS_SECRET_ACCESS_KEY`
  """

  require Logger

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.ExternalCosts.ExternalCost

  # ── OpenAI pricing (USD per 1M tokens, as of 2025) ────────────
  # Format: %{model_prefix => {input_per_m, output_per_m}}
  @openai_pricing %{
    "gpt-4o-mini" => {0.150, 0.600},
    "gpt-4o" => {5.000, 15.000},
    "gpt-4-turbo" => {10.00, 30.000},
    "gpt-4" => {30.00, 60.000},
    "gpt-3.5-turbo" => {0.500, 1.500},
    "text-embedding-3-small" => {0.020, 0.020},
    "text-embedding-3-large" => {0.130, 0.130},
    "text-embedding-ada-002" => {0.100, 0.100}
  }

  # Whereby: $0.004 per participant-minute (estimate for starter plan)
  @whereby_cost_per_minute 0.004

  # How many days back to sync
  @sync_days 30

  # ── Public API ─────────────────────────────────────────────────

  @doc """
  Syncs all external services. Returns a map of results per service.
  """
  def sync_all do
    %{
      openai: sync_openai(),
      whereby: sync_whereby(),
      evolution_api: sync_evolution_api(),
      aws_app_runner: sync_aws_app_runner()
    }
  end

  # ── OpenAI ─────────────────────────────────────────────────────

  @doc """
  Pulls OpenAI usage for the last `@sync_days` days and upserts into external_costs.
  Returns {:ok, %{rows_upserted: N}} or {:error, reason}.
  """
  def sync_openai do
    api_key = Application.get_env(:ledgr, :hello_doctor_openai_api_key)

    if is_nil(api_key) do
      {:error, :not_configured}
    else
      today = Date.utc_today()
      start_date = Date.add(today, -@sync_days)
      do_sync_openai(api_key, start_date, today)
    end
  end

  defp do_sync_openai(api_key, start_date, end_date) do
    start_unix = DateTime.to_unix(DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC"))
    end_unix = DateTime.to_unix(DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC"))

    url =
      "https://api.openai.com/v1/organization/usage/completions" <>
        "?start_time=#{start_unix}&end_time=#{end_unix}&bucket_width=1d&limit=100"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case :httpc.request(
           :get,
           {String.to_charlist(url),
            Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)},
           [],
           []
         ) do
      {:ok, {{_, 200, _}, _resp_headers, body}} ->
        parsed = Jason.decode!(List.to_string(body))
        rows = parse_and_upsert_openai_completions(parsed)

        # Also sync embeddings
        embed_url =
          "https://api.openai.com/v1/organization/usage/embeddings" <>
            "?start_time=#{start_unix}&end_time=#{end_unix}&bucket_width=1d&limit=100"

        embed_rows =
          case :httpc.request(
                 :get,
                 {String.to_charlist(embed_url),
                  Enum.map(headers, fn {k, v} ->
                    {String.to_charlist(k), String.to_charlist(v)}
                  end)},
                 [],
                 []
               ) do
            {:ok, {{_, 200, _}, _, embed_body}} ->
              embed_parsed = Jason.decode!(List.to_string(embed_body))
              parse_and_upsert_openai_embeddings(embed_parsed)

            _ ->
              0
          end

        {:ok, %{rows_upserted: rows + embed_rows}}

      {:ok, {{_, status, _}, _, body}} ->
        Logger.warning("[BillingSync.OpenAI] HTTP #{status}: #{List.to_string(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("[BillingSync.OpenAI] Request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_and_upsert_openai_completions(%{"data" => buckets}) when is_list(buckets) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.reduce(buckets, 0, fn bucket, count ->
      # Each bucket has: start_time (unix), end_time, results (list of per-model usage)
      bucket_date = unix_to_date(bucket["start_time"])

      results = Map.get(bucket, "results", [])

      Enum.reduce(results, count, fn result, inner_count ->
        model = result["model"] || "unknown"
        input_tokens = result["input_tokens"] || 0
        output_tokens = result["output_tokens"] || 0

        {input_price, output_price} = pricing_for_model(model)
        amount_usd = (input_tokens * input_price + output_tokens * output_price) / 1_000_000.0

        # Only upsert if there was actual usage
        if input_tokens + output_tokens > 0 do
          upsert_external_cost(%{
            service: "openai",
            date: bucket_date,
            model: model,
            amount_usd: amount_usd,
            units: input_tokens + output_tokens,
            unit_type: "tokens",
            raw_response: %{
              "input_tokens" => input_tokens,
              "output_tokens" => output_tokens,
              "model" => model
            },
            synced_at: now
          })

          inner_count + 1
        else
          inner_count
        end
      end)
    end)
  end

  defp parse_and_upsert_openai_completions(_), do: 0

  defp parse_and_upsert_openai_embeddings(%{"data" => buckets}) when is_list(buckets) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.reduce(buckets, 0, fn bucket, count ->
      bucket_date = unix_to_date(bucket["start_time"])
      results = Map.get(bucket, "results", [])

      Enum.reduce(results, count, fn result, inner_count ->
        model = result["model"] || "unknown"
        input_tokens = result["input_tokens"] || 0

        {input_price, _} = pricing_for_model(model)
        amount_usd = input_tokens * input_price / 1_000_000.0

        if input_tokens > 0 do
          upsert_external_cost(%{
            service: "openai",
            date: bucket_date,
            model: "#{model}:embed",
            amount_usd: amount_usd,
            units: input_tokens,
            unit_type: "tokens",
            raw_response: %{
              "input_tokens" => input_tokens,
              "model" => model,
              "type" => "embeddings"
            },
            synced_at: now
          })

          inner_count + 1
        else
          inner_count
        end
      end)
    end)
  end

  defp parse_and_upsert_openai_embeddings(_), do: 0

  defp pricing_for_model(model) do
    # Find the first matching prefix in our pricing map
    case Enum.find(@openai_pricing, fn {prefix, _} -> String.starts_with?(model, prefix) end) do
      {_, prices} -> prices
      # conservative fallback
      nil -> {1.00, 3.00}
    end
  end

  # ── Whereby ────────────────────────────────────────────────────

  @doc """
  Fetches Whereby meetings for the last `@sync_days` days,
  sums duration per day, and upserts into external_costs.
  """
  def sync_whereby do
    api_key = Application.get_env(:ledgr, :hello_doctor_whereby_api_key)

    if is_nil(api_key) do
      {:error, :not_configured}
    else
      today = Date.utc_today()
      start_date = Date.add(today, -@sync_days)
      do_sync_whereby(api_key, start_date, today)
    end
  end

  defp do_sync_whereby(api_key, start_date, _end_date) do
    created_after = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC") |> DateTime.to_iso8601()

    url =
      "https://api.whereby.dev/v1/meetings?createdAfter=#{URI.encode(created_after)}&limit=100"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case fetch_whereby_meetings(url, headers, []) do
      {:ok, meetings} ->
        rows = upsert_whereby_by_day(meetings)
        {:ok, %{rows_upserted: rows, meetings_fetched: length(meetings)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_whereby_meetings(url, headers, acc) do
    http_headers =
      Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    case :httpc.request(:get, {String.to_charlist(url), http_headers}, [], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        case Jason.decode!(List.to_string(body)) do
          %{"results" => meetings, "nextCursor" => cursor} when is_binary(cursor) ->
            next_url = "#{url}&cursor=#{URI.encode(cursor)}"
            fetch_whereby_meetings(next_url, headers, acc ++ meetings)

          %{"results" => meetings} ->
            {:ok, acc ++ meetings}

          other ->
            Logger.warning("[BillingSync.Whereby] Unexpected response shape: #{inspect(other)}")
            {:ok, acc}
        end

      {:ok, {{_, status, _}, _, body}} ->
        Logger.warning("[BillingSync.Whereby] HTTP #{status}: #{List.to_string(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("[BillingSync.Whereby] Request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp upsert_whereby_by_day(meetings) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Group meetings by the date they were created; estimate duration
    by_day =
      meetings
      |> Enum.group_by(fn m ->
        case DateTime.from_iso8601(m["createdAt"] || "") do
          {:ok, dt, _} -> DateTime.to_date(dt)
          _ -> nil
        end
      end)
      |> Map.delete(nil)

    Enum.reduce(by_day, 0, fn {day, day_meetings}, count ->
      # Whereby rooms don't always expose session duration; we estimate from
      # endDate - startDate where available, else use a 30-minute default.
      total_minutes =
        Enum.reduce(day_meetings, 0, fn m, acc ->
          duration = estimated_meeting_duration_minutes(m)
          acc + duration
        end)

      amount_usd = total_minutes * @whereby_cost_per_minute

      upsert_external_cost(%{
        service: "whereby",
        date: day,
        model: nil,
        amount_usd: amount_usd,
        units: total_minutes * 1.0,
        unit_type: "minutes",
        raw_response: %{
          "meeting_count" => length(day_meetings),
          "total_minutes" => total_minutes,
          "cost_per_minute" => @whereby_cost_per_minute
        },
        synced_at: now
      })

      count + 1
    end)
  end

  defp estimated_meeting_duration_minutes(meeting) do
    start_dt = meeting["startDate"] || meeting["createdAt"]
    end_dt = meeting["endDate"]

    cond do
      is_binary(start_dt) and is_binary(end_dt) ->
        with {:ok, s, _} <- DateTime.from_iso8601(start_dt),
             {:ok, e, _} <- DateTime.from_iso8601(end_dt) do
          max(DateTime.diff(e, s) |> div(60), 1)
        else
          _ -> 30
        end

      true ->
        30
    end
  end

  # ── Evolution API ──────────────────────────────────────────────

  @doc "Evolution API (Zenzeia) has no billing endpoint — always returns :not_supported."
  def sync_evolution_api, do: {:ok, :not_supported}

  # ── AWS App Runner ─────────────────────────────────────────────

  @doc """
  Queries AWS Cost Explorer for App Runner costs in the last `@sync_days` days.
  Requires HELLO_DOCTOR_AWS_ACCESS_KEY_ID and HELLO_DOCTOR_AWS_SECRET_ACCESS_KEY
  (an IAM user/role with ce:GetCostAndUsage on the us-east-1 account).
  """
  def sync_aws_app_runner do
    access_key_id = Application.get_env(:ledgr, :hello_doctor_aws_access_key_id)
    secret_access_key = Application.get_env(:ledgr, :hello_doctor_aws_secret_access_key)

    cond do
      is_nil(access_key_id) -> {:error, :aws_access_key_not_configured}
      is_nil(secret_access_key) -> {:error, :aws_secret_key_not_configured}
      true -> do_sync_aws_app_runner(access_key_id, secret_access_key)
    end
  end

  defp do_sync_aws_app_runner(access_key_id, secret_access_key) do
    today = Date.utc_today()
    start_date = Date.add(today, -@sync_days)

    body =
      Jason.encode!(%{
        "TimePeriod" => %{
          "Start" => Date.to_iso8601(start_date),
          "End" => Date.to_iso8601(today)
        },
        "Granularity" => "DAILY",
        "Filter" => %{
          "Dimensions" => %{
            "Key" => "SERVICE",
            "Values" => ["AWS App Runner"]
          }
        },
        "Metrics" => ["BlendedCost"],
        "GroupBy" => []
      })

    host = "ce.us-east-1.amazonaws.com"
    endpoint = "https://#{host}/"
    region = "us-east-1"
    service = "ce"
    action = "CostExplorer_20170110.GetCostAndUsage"

    case aws_post(endpoint, host, region, service, action, body, access_key_id, secret_access_key) do
      {:ok, response_body} ->
        data = Jason.decode!(response_body)
        rows = parse_and_upsert_aws_costs(data)
        {:ok, %{rows_upserted: rows}}

      {:error, reason} ->
        Logger.error("[BillingSync.AWS] Cost Explorer failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_and_upsert_aws_costs(%{"ResultsByTime" => results}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.reduce(results, 0, fn result, count ->
      start_str = get_in(result, ["TimePeriod", "Start"])
      amount_str = get_in(result, ["Total", "BlendedCost", "Amount"]) || "0"
      estimated = result["Estimated"] || false

      with {:ok, day} <- Date.from_iso8601(start_str),
           {amount, _} <- Float.parse(amount_str),
           true <- amount > 0 or not estimated do
        upsert_external_cost(%{
          service: "aws_app_runner",
          date: day,
          model: nil,
          amount_usd: amount,
          units: amount,
          unit_type: "usd",
          raw_response: %{
            "blended_cost" => amount_str,
            "estimated" => estimated
          },
          synced_at: now
        })

        count + 1
      else
        _ -> count
      end
    end)
  end

  defp parse_and_upsert_aws_costs(_), do: 0

  # ── AWS SigV4 signing ──────────────────────────────────────────

  defp aws_post(url, host, region, service, action, body, access_key_id, secret_access_key) do
    now = DateTime.utc_now()
    amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    date_stamp = Calendar.strftime(now, "%Y%m%d")

    body_hash = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

    canonical_headers =
      "content-type:application/x-amz-json-1.1\n" <>
        "host:#{host}\n" <>
        "x-amz-date:#{amz_date}\n" <>
        "x-amz-target:#{action}\n"

    signed_headers = "content-type;host;x-amz-date;x-amz-target"

    canonical_request =
      "POST\n/\n\n#{canonical_headers}\n#{signed_headers}\n#{body_hash}"

    credential_scope = "#{date_stamp}/#{region}/#{service}/aws4_request"

    string_to_sign =
      "AWS4-HMAC-SHA256\n#{amz_date}\n#{credential_scope}\n" <>
        (:crypto.hash(:sha256, canonical_request) |> Base.encode16(case: :lower))

    signing_key =
      hmac_sha256("AWS4#{secret_access_key}", date_stamp)
      |> hmac_sha256(region)
      |> hmac_sha256(service)
      |> hmac_sha256("aws4_request")

    signature = hmac_sha256(signing_key, string_to_sign) |> Base.encode16(case: :lower)

    auth_header =
      "AWS4-HMAC-SHA256 Credential=#{access_key_id}/#{credential_scope}, " <>
        "SignedHeaders=#{signed_headers}, Signature=#{signature}"

    http_headers = [
      {~c"Content-Type", ~c"application/x-amz-json-1.1"},
      {~c"X-Amz-Date", String.to_charlist(amz_date)},
      {~c"X-Amz-Target", String.to_charlist(action)},
      {~c"Authorization", String.to_charlist(auth_header)}
    ]

    case :httpc.request(
           :post,
           {String.to_charlist(url), http_headers, ~c"application/x-amz-json-1.1", body},
           [{:ssl, [{:verify, :verify_none}]}],
           []
         ) do
      {:ok, {{_, 200, _}, _, resp_body}} ->
        {:ok, List.to_string(resp_body)}

      {:ok, {{_, status, _}, _, resp_body}} ->
        Logger.warning("[BillingSync.AWS] HTTP #{status}: #{List.to_string(resp_body)}")
        {:error, {:http_error, status, List.to_string(resp_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp hmac_sha256(key, data) when is_binary(key) and is_binary(data) do
    :crypto.mac(:hmac, :sha256, key, data)
  end

  # ── Upsert helper ──────────────────────────────────────────────

  defp upsert_external_cost(attrs) do
    # Partial unique indexes require unsafe_fragment to pass the WHERE predicate
    # to PostgreSQL's ON CONFLICT inference clause.
    conflict_target =
      if attrs.model do
        {:unsafe_fragment, "(service, date, model) WHERE model IS NOT NULL"}
      else
        {:unsafe_fragment, "(service, date) WHERE model IS NULL"}
      end

    %ExternalCost{}
    |> ExternalCost.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:amount_usd, :units, :raw_response, :synced_at, :updated_at]},
      conflict_target: conflict_target
    )
  end

  # ── Date helpers ───────────────────────────────────────────────

  defp unix_to_date(nil), do: Date.utc_today()

  defp unix_to_date(unix) when is_integer(unix) do
    DateTime.from_unix!(unix) |> DateTime.to_date()
  end
end
