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

    # Filter to just the HelloDoctor OpenAI project. The admin key has org-wide
    # access, so without this we'd pull costs from ALL projects in the org
    # (LiveMed-MC, AumentaMiPension, etc.) and book them as HelloDoctor expense.
    # Erlang's :httpc rejects literal [] in URIs — they must be percent-encoded.
    project_filter =
      case Application.get_env(:ledgr, :hello_doctor_openai_project_id) do
        nil -> ""
        id -> "&project_ids%5B%5D=#{URI.encode_www_form(id)}"
      end

    # /v1/organization/costs returns the actual billed $ (post-discount,
    # current-price) per project per day. We group_by=line_item so we get a
    # per-model breakdown AND because OpenAI's project_ids filter only takes
    # effect when paired with a group_by; without one the API returns
    # whichever project's data it lists first instead of filtering.
    base_url =
      "https://api.openai.com/v1/organization/costs" <>
        "?start_time=#{start_unix}&end_time=#{end_unix}" <>
        "&bucket_width=1d&limit=31&group_by%5B%5D=line_item" <>
        project_filter

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case fetch_all_openai_cost_pages(base_url, headers, []) do
      {:ok, buckets} ->
        rows = parse_and_upsert_openai_costs(buckets)
        {:ok, %{rows_upserted: rows}}

      {:error, reason} ->
        Logger.error("[BillingSync.OpenAI] Cost fetch failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Cursor-paginates /organization/costs via the `next_page` token until
  # has_more=false. Cost data is small (~hundreds of bytes per bucket) so we
  # accumulate in memory.
  defp fetch_all_openai_cost_pages(url, headers, acc) do
    http_headers =
      Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    case :httpc.request(:get, {String.to_charlist(url), http_headers}, [], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        parsed = Jason.decode!(List.to_string(body))
        buckets = Map.get(parsed, "data", [])
        new_acc = acc ++ buckets

        if parsed["has_more"] && parsed["next_page"] do
          next_url = url <> "&page=#{URI.encode_www_form(parsed["next_page"])}"
          fetch_all_openai_cost_pages(next_url, headers, new_acc)
        else
          {:ok, new_acc}
        end

      {:ok, {{_, status, _}, _, body}} ->
        Logger.warning("[BillingSync.OpenAI] HTTP #{status}: #{List.to_string(body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_and_upsert_openai_costs(buckets) when is_list(buckets) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # OpenAI returns multiple results per bucket (one per line_item: input,
    # cached input, output, embedding, etc.). Aggregate (date, model) → totals.
    totals =
      Enum.reduce(buckets, %{}, fn bucket, acc ->
        bucket_date = unix_to_date(bucket["start_time"])
        results = Map.get(bucket, "results", [])

        Enum.reduce(results, acc, fn result, inner_acc ->
          usd = parse_amount(get_in(result, ["amount", "value"]))
          quantity = parse_amount(result["quantity"])
          line_item = result["line_item"]
          model = base_model_from_line_item(line_item)
          key = {bucket_date, model}

          current = Map.get(inner_acc, key, %{usd: 0.0, qty: 0.0, lines: %{}})

          Map.put(inner_acc, key, %{
            usd: current.usd + usd,
            qty: current.qty + quantity,
            lines: Map.update(current.lines, line_item || "(no line_item)", usd, &(&1 + usd))
          })
        end)
      end)

    Enum.reduce(totals, 0, fn {{date, model}, %{usd: usd, qty: qty, lines: lines}}, count ->
      if usd > 0 do
        upsert_external_cost(%{
          service: "openai",
          date: date,
          model: model,
          amount_usd: usd,
          units: qty,
          unit_type: "tokens",
          raw_response: %{
            "line_items" => lines,
            "total_quantity" => qty,
            "model" => model,
            "source" => "openai_costs_endpoint"
          },
          synced_at: now
        })

        count + 1
      else
        count
      end
    end)
  end

  # OpenAI returns amount.value as a high-precision string (e.g.
  # "0.0408070500..."), not a number. Quantity can be float or null.
  defp parse_amount(nil), do: 0.0
  defp parse_amount(v) when is_number(v), do: v * 1.0

  defp parse_amount(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      _ -> 0.0
    end
  end

  # line_item looks like "gpt-4o-mini-2024-07-18, input" or
  # "text-embedding-3-small, input" — keep just the model name before the comma.
  defp base_model_from_line_item(nil), do: "unknown"

  defp base_model_from_line_item(line_item) when is_binary(line_item) do
    case String.split(line_item, ",", parts: 2) do
      [model | _] -> String.trim(model)
      _ -> line_item
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
          # Whereby returns "cursor" (not "nextCursor") for pagination. The field
          # is present even on the last page (with no more results), so cap at
          # 1000 meetings as a safety net and stop when "results" is empty.
          %{"results" => meetings, "cursor" => cursor}
          when is_binary(cursor) and meetings != [] and length(acc) < 1000 ->
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

    # Group meetings by the date they were created. Whereby's response uses
    # `startDate` (the room's start time) — NOT `createdAt`, which doesn't exist
    # in their meetings endpoint.
    by_day =
      meetings
      |> Enum.group_by(fn m ->
        case DateTime.from_iso8601(m["startDate"] || "") do
          {:ok, dt, _} -> DateTime.to_date(dt)
          _ -> nil
        end
      end)
      |> Map.delete(nil)

    Enum.reduce(by_day, 0, fn {day, day_meetings}, count ->
      # `endDate` is the ROOM EXPIRY (often days/months in the future), NOT the
      # session end, so we can't use it to compute call duration. Estimate a
      # fixed 30 minutes per meeting until Whereby exposes real session length.
      total_minutes = length(day_meetings) * 30

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
          "cost_per_minute" => @whereby_cost_per_minute,
          "duration_source" => "30min_default"
        },
        synced_at: now
      })

      count + 1
    end)
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
    # The X-Amz-Target header for Cost Explorer uses the internal service name
    # "AWSInsightsIndexService", not "CostExplorer_<version>". Sending the
    # latter results in UnknownOperationException.
    action = "AWSInsightsIndexService.GetCostAndUsage"

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
