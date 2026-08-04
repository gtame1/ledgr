defmodule Ledgr.Domains.HelloDoctor.CsvEncoding do
  @moduledoc """
  Encoding guards shared by the HelloDoctor CSV importers.

  This lives in one place on purpose. The importers are a copy-paste family
  ("mirrors DoctorPayoutImport"), which is how the defect below reached both of
  them; duplicating the guard — and the reasoning behind it — is how it would
  reach the next one.

  Callers wrap the returned `{line, message}` in their own error shape, since
  those differ (the marketing importer also carries a `skipped` count).
  """

  @bom <<0xEF, 0xBB, 0xBF>>

  @doc """
  `:ok` when `csv` is valid UTF-8, else `{:error, {line, message}}` naming the
  first offending line.

  Excel-for-Mac's plain "CSV" export writes Mac Roman, not UTF-8, so accented
  text ("Ginecología") arrives as bytes that aren't valid UTF-8 at all. Every
  String function in the importers passes such bytes through untouched rather
  than raising, so a bad file parses clean and only blows up at INSERT, where
  Postgres rejects it (22021 invalid byte sequence for encoding "UTF8") — an
  unrescued Postgrex.Error, i.e. a 500 instead of the normal error report.

  We reject rather than transcode because the source encoding is unknowable:
  byte 0x92 is "í" in Mac Roman but "'" in CP-1252. A wrong guess corrupts the
  text silently, and in the marketing importer it would also shift the
  DB-generated `dedup_hash`, so a later correct upload would re-insert every row.
  """
  def validate(csv) when is_binary(csv) do
    if String.valid?(csv) do
      :ok
    else
      {:error, {first_invalid_line(csv), message()}}
    end
  end

  @doc """
  Strips the UTF-8 BOM that Excel's "CSV UTF-8" export prepends — the very
  export users reach for to fix the Mac Roman problem above.

  Left in place the BOM binds to the first header cell, making it "<BOM>date",
  so header validation reports a required column as missing on a file that is
  in fact correct. Spelled as raw bytes because a literal U+FEFF in source
  would be invisible in every editor and diff.
  """
  def strip_bom(@bom <> rest), do: rest
  def strip_bom(csv) when is_binary(csv), do: csv

  defp message do
    ~s(file is not valid UTF-8 text. Re-export it as "CSV UTF-8" — on macOS a ) <>
      ~s(plain "CSV"/"Comma Separated Values" export writes Mac Roman, which ) <>
      ~s(corrupts accented text. Nothing was read.)
  end

  # Mirrors the importers' split_lines/1 so the number matches how they number
  # rows: blank lines dropped, header = 1, first data row = 2.
  defp first_invalid_line(csv) do
    csv
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.with_index(1)
    |> Enum.find_value(0, fn {line, n} -> if !String.valid?(line), do: n end)
  end
end
