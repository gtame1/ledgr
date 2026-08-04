defmodule Ledgr.Domains.HelloDoctor.DoctorPayoutImport do
  @moduledoc """
  Bulk-import doctor payouts from CSV.

  Expected CSV columns (header row required):
    doctor_id      — required, must match an existing Doctor.id
    amount         — required, MXN pesos (e.g. "100.00")
    date           — optional, ISO 8601 (YYYY-MM-DD); defaults to today
    description    — optional; defaults to "Doctor payout — <doctor name>"
    doctor_name    — optional, informational

  For each row, creates a journal entry:
    DEBIT  2000 Doctor Payable   [amount]
    CREDIT 1010 Bank - MXN       [amount]

  All rows are validated before any are written. The whole import runs
  inside a transaction — if any row fails, nothing is persisted.
  """

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.HelloDoctor.CsvEncoding
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor

  @doctor_payable_code "2000"
  @bank_mxn_code "1010"

  @doc """
  Parses a CSV string and returns either:
    {:ok, %{rows: [...], errors: []}}                  — ready to commit
    {:error, %{rows: [...], errors: [{row_n, msg}]}}   — has issues

  The file must be UTF-8; see `CsvEncoding.validate/1` for why we reject rather
  than transcode.
  """
  def parse(csv_string) when is_binary(csv_string) do
    case CsvEncoding.validate(csv_string) do
      :ok -> csv_string |> CsvEncoding.strip_bom() |> parse_utf8()
      {:error, {line, msg}} -> {:error, %{rows: [], errors: [{line, msg}]}}
    end
  end

  defp parse_utf8(csv_string) do
    default_date = Ledgr.Domains.HelloDoctor.today()

    case split_lines(csv_string) do
      [] ->
        {:error, %{rows: [], errors: [{0, "CSV is empty"}]}}

      [header_line | data_lines] ->
        header = parse_line(header_line) |> Enum.map(&normalize_header/1)

        case validate_header(header) do
          :ok ->
            doctors_by_id = preload_doctors()

            {rows, errors} =
              data_lines
              |> Enum.with_index(2)
              |> Enum.reject(fn {line, _i} -> String.trim(line) == "" end)
              |> Enum.map_reduce([], fn {line, row_num}, errs ->
                case parse_row(line, header, doctors_by_id, default_date) do
                  {:ok, row} -> {row, errs}
                  {:error, msg} -> {nil, [{row_num, msg} | errs]}
                end
              end)

            rows = Enum.reject(rows, &is_nil/1)
            errors = Enum.reverse(errors)

            if errors == [] do
              {:ok, %{rows: rows, errors: []}}
            else
              {:error, %{rows: rows, errors: errors}}
            end

          {:error, msg} ->
            {:error, %{rows: [], errors: [{1, msg}]}}
        end
    end
  end

  @doc """
  Commits a list of parsed rows as journal entries in a single transaction.
  Returns {:ok, count} or {:error, reason}.
  """
  def commit(rows) when is_list(rows) do
    doctor_payable = Accounting.get_account_by_code!(@doctor_payable_code)
    bank_mxn = Accounting.get_account_by_code!(@bank_mxn_code)

    Repo.transaction(fn ->
      Enum.reduce_while(rows, 0, fn row, acc ->
        case create_entry(row, doctor_payable, bank_mxn) do
          {:ok, _} -> {:cont, acc + 1}
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

  # ── Per-row entry creation ─────────────────────────────────────

  defp create_entry(row, doctor_payable, bank_mxn) do
    amount_cents = round(row.amount * 100)

    entry_attrs = %{
      date: row.date,
      entry_type: "doctor_payout",
      reference: "DoctorPayout-#{row.doctor_id}",
      description: row.description,
      payee: row.doctor_name || "Doctor ##{row.doctor_id}"
    }

    lines = [
      %{
        account_id: doctor_payable.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Clearing doctor payable — #{row.description}"
      },
      %{
        account_id: bank_mxn.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Bank transfer to doctor — #{row.description}"
      }
    ]

    Accounting.create_journal_entry_with_lines(entry_attrs, lines)
  end

  # ── CSV parsing helpers ────────────────────────────────────────

  defp split_lines(csv) do
    csv
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  # Minimal RFC-4180-ish line parser: handles quoted fields and escaped quotes.
  defp parse_line(line) do
    {fields, current, _in_quote} =
      line
      |> String.graphemes()
      |> Enum.reduce({[], "", false}, fn
        ~s("), {fields, current, false} ->
          {fields, current, true}

        ~s("), {fields, current, true} ->
          {fields, current, false}

        ",", {fields, current, false} ->
          {[current | fields], "", false}

        ch, {fields, current, in_quote} ->
          {fields, current <> ch, in_quote}
      end)

    [current | fields] |> Enum.reverse() |> Enum.map(&String.trim/1)
  end

  defp normalize_header(h) do
    h |> String.downcase() |> String.trim() |> String.replace(~r/[\s-]+/, "_")
  end

  defp validate_header(header) do
    required = ["doctor_id", "amount"]
    missing = required -- header

    case missing do
      [] -> :ok
      [_ | _] -> {:error, "Missing required column(s): #{Enum.join(missing, ", ")}"}
    end
  end

  defp parse_row(line, header, doctors_by_id, default_date) do
    values = parse_line(line)
    row = Enum.zip(header, values) |> Enum.into(%{})

    with {:ok, doctor_id} <- fetch_required(row, "doctor_id"),
         {:ok, doctor} <- find_doctor(doctor_id, doctors_by_id),
         {:ok, amount_str} <- fetch_required(row, "amount"),
         {:ok, amount} <- parse_amount(amount_str),
         {:ok, date} <- parse_date(Map.get(row, "date"), default_date) do
      doctor_name = Map.get(row, "doctor_name") || doctor.name
      description = Map.get(row, "description") || "Doctor payout — #{doctor_name}"

      {:ok,
       %{
         doctor_id: doctor.id,
         doctor_name: doctor_name,
         amount: amount,
         date: date,
         description: description
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

  defp find_doctor(id, doctors_by_id) do
    case Map.get(doctors_by_id, id) do
      nil -> {:error, "unknown doctor_id: #{id}"}
      doctor -> {:ok, doctor}
    end
  end

  defp parse_amount(str) do
    cleaned = str |> String.replace(",", "") |> String.trim()

    case Float.parse(cleaned) do
      {amount, ""} when amount > 0 -> {:ok, amount}
      {amount, ""} -> {:error, "amount must be > 0 (got #{amount})"}
      _ -> {:error, "invalid amount: #{inspect(str)}"}
    end
  end

  defp parse_date(nil, default), do: {:ok, default}
  defp parse_date("", default), do: {:ok, default}

  defp parse_date(str, _default) do
    case Date.from_iso8601(str) do
      {:ok, d} -> {:ok, d}
      _ -> {:error, "invalid date (expected YYYY-MM-DD): #{inspect(str)}"}
    end
  end

  defp preload_doctors do
    import Ecto.Query, only: [from: 2]
    Repo.all(from d in Doctor, select: {d.id, d}) |> Map.new()
  end
end
