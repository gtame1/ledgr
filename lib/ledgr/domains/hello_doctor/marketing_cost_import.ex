defmodule Ledgr.Domains.HelloDoctor.MarketingCostImport do
  @moduledoc """
  Bulk-import marketing / ad spend from CSV (platform + date totals).

  Expected CSV columns (header row required):
    date        — required, ISO 8601 (YYYY-MM-DD)
    platform    — required, e.g. "meta", "google"
    amount      — required, spend in `currency` (e.g. "1234.56"); negative for
                  a credit (e.g. "-2577.56")
    currency    — optional, "MXN" (default) or "USD"
    description — optional

  Each row inserts a `marketing_costs` row (source "csv") and posts it to the
  GL (DEBIT 6050 / CREDIT 2310 — flipped for a credit). All rows are validated
  before any are written; the whole import runs in one transaction.

  Ad billing has many charges per platform per day (a Meta charge per ad set,
  several Google charges/day), so a charge is identified by
  `{platform, date, description}` — its *identity* — and `amount` is the
  mutable fact about it. Each parsed row is therefore one of three things:

    * **new** — no charge with that identity exists yet; insert it.
    * **restated** — the identity exists with a *different* amount. The
      platform revised the figure, so we UPDATE the existing row and post a
      GL adjustment for the delta. We do not insert a second row.
    * **unchanged** — identity and amount both already present; skip silently.

  That middle case is the whole point. Google settles an invoice over days
  ("Servicio - Search - MX" on 2026-07-03 went 310.30 → 310.31 → 310.32), and
  an early upload of the current day captures only partial spend. When `amount`
  was part of the identity, every restatement imported as a brand-new charge:
  re-uploading Jun–Aug once triple-counted some days and put $10,919 of
  phantom spend in the ledger, which had to be cleaned out by hand.

  **A charge with a blank description can't take part in this.** Its identity
  would collapse to `{platform, date}`, which genuinely has many rows a day, so
  a blank-description row falls back to exact `{platform, date, amount}`
  matching — insert-or-skip, never restate. Older Google exports had no
  description column, which is exactly how the June duplicates arose; keep the
  description column populated and restatements resolve themselves.
  """

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.CsvEncoding
  alias Ledgr.Domains.HelloDoctor.MarketingCosts.MarketingCost
  alias Ledgr.Domains.HelloDoctor.MarketingCostAccounting

  import Ecto.Query, only: [from: 2]

  @valid_currencies ~w[MXN USD]

  @doc """
  Parses a CSV string. Returns
  `{:ok, %{rows: [...], restatements: [...], errors: [], skipped: n}}` when
  every row validates, or `{:error, %{...}}` when any row fails.

    * `rows`         — charges to insert.
    * `restatements` — `%{cost: %MarketingCost{}, row: parsed, delta: float}`
      for each identity whose amount changed. `delta` is the signed change in
      the uploaded currency.
    * `skipped`      — rows already present, identity and amount both matching.

  The file must be UTF-8; see `CsvEncoding.validate/1` for why we reject rather
  than transcode.
  """
  def parse(csv_string) when is_binary(csv_string) do
    case CsvEncoding.validate(csv_string) do
      :ok -> csv_string |> CsvEncoding.strip_bom() |> parse_utf8()
      {:error, {line, msg}} -> {:error, empty_result([{line, msg}])}
    end
  end

  defp empty_result(errors),
    do: %{rows: [], restatements: [], errors: errors, skipped: 0}

  defp parse_utf8(csv_string) do
    case split_lines(csv_string) do
      [] ->
        {:error, empty_result([{0, "CSV is empty"}])}

      [header_line | data_lines] ->
        header = parse_line(header_line) |> Enum.map(&normalize_header/1)

        case validate_header(header) do
          :ok -> classify_rows(data_lines, header)
          {:error, msg} -> {:error, empty_result([{1, msg}])}
        end
    end
  end

  defp classify_rows(data_lines, header) do
    by_identity = existing_by_identity()
    exact = existing_exact_keys()

    acc = %{
      rows: [],
      restatements: [],
      errors: [],
      skipped: 0,
      seen: MapSet.new(),
      seen_identity: MapSet.new()
    }

    acc =
      data_lines
      |> Enum.with_index(2)
      |> Enum.reject(fn {line, _i} -> String.trim(line) == "" end)
      |> Enum.reduce(acc, fn {line, row_num}, acc ->
        case parse_row(line, header) do
          {:ok, row} -> classify_row(row, row_num, acc, by_identity, exact)
          {:error, msg} -> %{acc | errors: [{row_num, msg} | acc.errors]}
        end
      end)

    result = %{
      rows: Enum.reverse(acc.rows),
      restatements: Enum.reverse(acc.restatements),
      errors: Enum.reverse(acc.errors),
      skipped: acc.skipped
    }

    if result.errors == [], do: {:ok, result}, else: {:error, result}
  end

  defp classify_row(row, row_num, acc, by_identity, exact) do
    cond do
      # Same charge twice inside one file — always a mistake in the export,
      # and silently taking one of them would hide it.
      MapSet.member?(acc.seen, dedup_key(row)) ->
        %{
          acc
          | errors: [
              {row_num, "duplicate of an earlier row in this file (#{label(row)})"} | acc.errors
            ]
        }

      # Identity + amount both already stored: nothing to do.
      MapSet.member?(exact, exact_key(row)) ->
        remember(acc, row, &%{&1 | skipped: &1.skipped + 1})

      # Two rows in ONE file claiming the same charge with different amounts.
      # Inserting both would manufacture the very ambiguity this module exists
      # to avoid — and the next upload couldn't tell which one it restates.
      identity(row) && MapSet.member?(acc.seen_identity, identity(row)) ->
        msg =
          "a different amount for #{label(row)} appears earlier in this file; " <>
            "one charge can only have one amount"

        %{acc | errors: [{row_num, msg} | acc.errors]}

      true ->
        case Map.get(by_identity, identity(row)) do
          # Blank description → no usable identity, so this is a new charge.
          # (identity/1 returns nil there, which never matches the map.)
          nil ->
            remember(acc, row, &%{&1 | rows: [row | &1.rows]})

          [%MarketingCost{} = cost] ->
            restatement = %{cost: cost, row: row, delta: row.amount - cost.amount}
            remember(acc, row, &%{&1 | restatements: [restatement | &1.restatements]})

          [_ | _] = many ->
            # Shouldn't happen — the importer never creates a second row for one
            # identity. Refuse rather than guess which one to restate.
            msg =
              "#{length(many)} existing charges share #{label(row)}; " <>
                "can't tell which one this restates — resolve them in the UI first"

            %{acc | errors: [{row_num, msg} | acc.errors]}
        end
    end
  end

  # Records that this file has now covered `row` — both its full tuple and its
  # identity — then applies `fun` to the accumulator.
  defp remember(acc, row, fun) do
    acc = %{
      acc
      | seen: MapSet.put(acc.seen, dedup_key(row)),
        seen_identity:
          if(identity(row),
            do: MapSet.put(acc.seen_identity, identity(row)),
            else: acc.seen_identity
          )
    }

    fun.(acc)
  end

  # The charge's identity: what makes two lines the *same* charge across
  # uploads. nil when the description is blank — such a row can't be matched
  # by identity at all (see the moduledoc).
  defp identity(%{platform: p, date: d, description: desc})
       when is_binary(desc) and desc != "",
       do: {p, d, desc}

  defp identity(_), do: nil

  # Human-readable row label for error messages. Tolerates a blank description,
  # which `identity/1` deliberately refuses to build a key from.
  defp label(%{platform: p, date: d, description: desc}) do
    if is_binary(desc) and desc != "", do: "#{p} / #{d} / #{desc}", else: "#{p} / #{d}"
  end

  # Identity + amount: an exact re-upload of something already stored.
  defp exact_key(%{platform: p, date: d, description: desc, amount: a}), do: {p, d, desc, a}

  # Within one file we still de-duplicate on the full tuple.
  defp dedup_key(row), do: exact_key(row)

  @doc """
  Applies a parse result.

  Given the whole parse map, inserts the new charges and applies the
  restatements, returning `{:ok, %{inserted: n, restated: n}}`.

  Given a bare list of rows (for callers that only have inserts), bulk-inserts
  them with `on_conflict: :nothing` keyed on the generated `dedup_hash` — so a
  re-submit, even a concurrent one, inserts ZERO duplicates — then posts only
  the genuinely-new rows to the GL and returns `{:ok, count}`.

  Each GL post runs in its own short transaction (via `post_to_gl/2`), so the
  import never holds one connection for the whole file — that long hold is what
  starved the pool and made the request look hung (→ users re-submitting).
  """
  def commit(%{rows: rows, restatements: restatements}) do
    {:ok, inserted} = commit(rows)

    restated =
      Enum.count(restatements, fn r ->
        match?({:ok, _}, MarketingCostAccounting.restate(r.cost, r.row.amount))
      end)

    {:ok, %{inserted: inserted, restated: restated}}
  end

  def commit(rows) when is_list(rows) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(rows, fn row ->
        %{
          platform: row.platform,
          date: row.date,
          amount: row.amount,
          currency: row.currency,
          description: row.description,
          source: "csv",
          inserted_at: now,
          updated_at: now
        }
      end)

    # ON CONFLICT DO NOTHING + RETURNING yields only the rows actually inserted,
    # so `inserted` excludes anything already present (idempotent).
    {_n, inserted} =
      Repo.insert_all(MarketingCost, entries,
        on_conflict: :nothing,
        conflict_target: :dedup_hash,
        returning: true
      )

    accts = MarketingCostAccounting.gl_accounts()
    Enum.each(inserted, &MarketingCostAccounting.post_to_gl(&1, accts))

    {:ok, length(inserted)}
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

  # A negative amount is a credit — a promo credit, refund or billing
  # adjustment on the platform's invoice. It posts to the GL with the debit and
  # credit sides flipped (see `MarketingCostAccounting.post_to_gl/2`), so it
  # reduces marketing expense instead of adding to it. Zero is accepted (the
  # downloadable template ships 0.00 example rows) but never posts.
  defp parse_amount(str) do
    cleaned = str |> String.replace(",", "") |> String.replace("$", "") |> String.trim()

    case Float.parse(cleaned) do
      {amount, ""} -> {:ok, amount}
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

  # Stored CSV charges keyed by identity {platform, date, description}, so a
  # re-upload can tell "this charge, restated" from "a new charge". Blank
  # descriptions are excluded: their identity isn't distinguishing, and
  # including them would let one blank row restate an unrelated one.
  #
  # The value is a LIST because the map must be able to represent an ambiguous
  # identity. It should always be one element; `classify_row/5` refuses to
  # guess if it isn't, rather than silently restating an arbitrary row.
  defp existing_by_identity do
    from(c in MarketingCost,
      where: c.source == "csv" and not is_nil(c.description) and c.description != ""
    )
    |> Repo.all()
    |> Enum.group_by(&{&1.platform, &1.date, &1.description})
  end

  # Identity + amount, for the "already stored, unchanged" check. Covers blank
  # descriptions too, which is the only matching a blank row gets.
  defp existing_exact_keys do
    Repo.all(
      from c in MarketingCost,
        where: c.source == "csv",
        select: {c.platform, c.date, c.description, c.amount}
    )
    |> MapSet.new()
  end
end
