defmodule Ledgr.Domains.HelloDoctor.MarketingCostImport do
  @moduledoc """
  Bulk-import marketing / ad spend from CSV (platform + date totals).

  Expected CSV columns (header row required):
    date        — required, ISO 8601 (YYYY-MM-DD)
    platform    — required, e.g. "meta", "google"
    amount      — required, spend in `currency` (e.g. "1234.56")
    currency    — optional, "MXN" (default) or "USD"
    description — optional

  Each row inserts a `marketing_costs` row (source "csv") and posts it to the
  GL (DEBIT 6050 / CREDIT 2310). All rows are validated before any are written;
  the whole import runs in one transaction. Re-importing a platform/date that
  already exists is rejected (delete the existing row first to correct it).
  """

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.MarketingCosts.MarketingCost
  alias Ledgr.Domains.HelloDoctor.MarketingCostAccounting

  import Ecto.Query, only: [from: 2]

  @valid_currencies ~w[MXN USD]

  @doc """
  Parses a CSV string. Returns `{:ok, %{rows: [...], errors: []}}` when clean,
  or `{:error, %{rows: [...], errors: [{row_n, msg}]}}`.
  """
  def parse(csv_string) when is_binary(csv_string) do
    case split_lines(csv_string) do
      [] ->
        {:error, %{rows: [], errors: [{0, "CSV is empty"}]}}

      [header_line | data_lines] ->
        header = parse_line(header_line) |> Enum.map(&normalize_header/1)

        case validate_header(header) do
          :ok ->
            existing = existing_keys()

            {rows, errors, _seen} =
              data_lines
              |> Enum.with_index(2)
              |> Enum.reject(fn {line, _i} -> String.trim(line) == "" end)
              |> Enum.reduce({[], [], MapSet.new()}, fn {line, row_num}, {rows, errs, seen} ->
                case parse_row(line, header) do
                  {:ok, row} ->
                    key = {row.platform, row.date}

                    cond do
                      MapSet.member?(seen, key) ->
                        {rows,
                         [
                           {row_num, "duplicate #{row.platform} / #{row.date} in this file"}
                           | errs
                         ], seen}

                      MapSet.member?(existing, key) ->
                        {rows,
                         [
                           {row_num,
                            "#{row.platform} spend for #{row.date} already imported — delete it first to re-import"}
                           | errs
                         ], seen}

                      true ->
                        {[row | rows], errs, MapSet.put(seen, key)}
                    end

                  {:error, msg} ->
                    {rows, [{row_num, msg} | errs], seen}
                end
              end)

            rows = Enum.reverse(rows)
            errors = Enum.reverse(errors)

            if errors == [],
              do: {:ok, %{rows: rows, errors: []}},
              else: {:error, %{rows: rows, errors: errors}}

          {:error, msg} ->
            {:error, %{rows: [], errors: [{1, msg}]}}
        end
    end
  end

  @doc """
  Commits parsed rows: inserts each marketing_cost and posts it to the GL, all
  in one transaction. Returns `{:ok, count}` or `{:error, row, reason}`.
  """
  def commit(rows) when is_list(rows) do
    Repo.transaction(fn ->
      Enum.reduce_while(rows, 0, fn row, acc ->
        with {:ok, cost} <- insert_cost(row),
             {:ok, _posted} <- MarketingCostAccounting.post_to_gl(cost) do
          {:cont, acc + 1}
        else
          {:error, reason} -> {:halt, {:error, row, reason}}
        end
      end)
    end)
    |> case do
      {:ok, {:error, row, reason}} -> {:error, row, reason}
      {:ok, count} when is_integer(count) -> {:ok, count}
      {:error, reason} -> {:error, nil, reason}
    end
  end

  defp insert_cost(row) do
    %MarketingCost{}
    |> MarketingCost.changeset(%{
      platform: row.platform,
      date: row.date,
      amount: row.amount,
      currency: row.currency,
      description: row.description,
      source: "csv"
    })
    |> Repo.insert()
  end

  # ── CSV parsing helpers (mirrors DoctorPayoutImport) ────────────

  defp split_lines(csv) do
    csv
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp parse_line(line) do
    {fields, current, _in_quote} =
      line
      |> String.graphemes()
      |> Enum.reduce({[], "", false}, fn
        ~s("), {fields, current, false} -> {fields, current, true}
        ~s("), {fields, current, true} -> {fields, current, false}
        ",", {fields, current, false} -> {[current | fields], "", false}
        ch, {fields, current, in_quote} -> {fields, current <> ch, in_quote}
      end)

    [current | fields] |> Enum.reverse() |> Enum.map(&String.trim/1)
  end

  defp normalize_header(h),
    do: h |> String.downcase() |> String.trim() |> String.replace(~r/[\s-]+/, "_")

  defp validate_header(header) do
    missing = ["date", "platform", "amount"] -- header

    if missing == [],
      do: :ok,
      else: {:error, "Missing required column(s): #{Enum.join(missing, ", ")}"}
  end

  defp parse_row(line, header) do
    row = header |> Enum.zip(parse_line(line)) |> Enum.into(%{})

    with {:ok, date_str} <- fetch_required(row, "date"),
         {:ok, date} <- parse_date(date_str),
         {:ok, platform} <- fetch_required(row, "platform"),
         {:ok, amount_str} <- fetch_required(row, "amount"),
         {:ok, amount} <- parse_amount(amount_str),
         {:ok, currency} <- parse_currency(Map.get(row, "currency")) do
      {:ok,
       %{
         date: date,
         platform: platform |> String.trim() |> String.downcase(),
         amount: amount,
         currency: currency,
         description: blank_to_nil(Map.get(row, "description"))
       }}
    end
  end

  defp fetch_required(row, key) do
    case Map.get(row, key) do
      nil -> {:error, "missing required field: #{key}"}
      "" -> {:error, "missing required field: #{key}"}
      v -> {:ok, v}
    end
  end

  defp parse_amount(str) do
    cleaned = str |> String.replace(",", "") |> String.replace("$", "") |> String.trim()

    case Float.parse(cleaned) do
      {amount, ""} when amount >= 0 -> {:ok, amount}
      {amount, ""} -> {:error, "amount must be >= 0 (got #{amount})"}
      _ -> {:error, "invalid amount: #{inspect(str)}"}
    end
  end

  defp parse_currency(nil), do: {:ok, "MXN"}
  defp parse_currency(""), do: {:ok, "MXN"}

  defp parse_currency(str) do
    up = str |> String.trim() |> String.upcase()

    if up in @valid_currencies,
      do: {:ok, up},
      else: {:error, "currency must be MXN or USD (got #{inspect(str)})"}
  end

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> {:ok, d}
      _ -> {:error, "invalid date (expected YYYY-MM-DD): #{inspect(str)}"}
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  # Existing platform-level CSV rows, as a {platform, date} set, to reject dups.
  defp existing_keys do
    Repo.all(
      from c in MarketingCost,
        where: c.source == "csv" and is_nil(c.campaign_id),
        select: {c.platform, c.date}
    )
    |> MapSet.new()
  end
end
