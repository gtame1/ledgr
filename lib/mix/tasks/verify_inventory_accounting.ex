defmodule Mix.Tasks.VerifyInventoryAccounting do
  @moduledoc """
  Verifies inventory accounting integrity.

  Usage: mix verify_inventory_accounting
  """
  use Mix.Task

  alias Ledgr.Domains.MrMunchMe.Inventory.Verification

  @shortdoc "Verifies inventory accounting integrity"

  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("\n🔍 Running inventory accounting verification...\n")
    IO.puts(String.duplicate("=", 60))
    IO.puts("")

    results = Verification.run_all_checks()

    # Report results
    Enum.each(results, fn {check_name, result} ->
      case result do
        {:ok, data} ->
          IO.puts("✅ #{format_check_name(check_name)}: OK")

          if is_map(data) do
            Enum.each(data, fn {k, v} ->
              IO.puts("   #{format_key(k)}: #{format_value(k, v)}")
            end)
          end

          IO.puts("")

        {:error, issues} ->
          IO.puts("❌ #{format_check_name(check_name)}: FAILED")

          if is_list(issues) do
            Enum.each(issues, fn issue -> IO.puts("   - #{issue}") end)
          else
            IO.puts("   - #{issues}")
          end

          IO.puts("")
      end
    end)

    IO.puts(String.duplicate("=", 60))

    # Summary
    total_checks = map_size(results)

    passed_checks =
      results
      |> Enum.count(fn {_, result} -> match?({:ok, _}, result) end)

    failed_checks = total_checks - passed_checks

    IO.puts("\nSummary: #{passed_checks}/#{total_checks} checks passed")

    if failed_checks > 0 do
      IO.puts("⚠️  #{failed_checks} check(s) failed. Please review the issues above.")
      System.halt(1)
    else
      IO.puts("✨ All checks passed!")
    end
  end

  defp format_check_name(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_key(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_value(key, value) when is_integer(value) do
    # Only format as currency if the key suggests it's a monetary value
    key_str = Atom.to_string(key)

    # Keys that are definitely counts, not currency
    is_count =
      String.starts_with?(key_str, "checked_") or
        key_str == "unbalanced" or
        key_str == "issues"

    # Keys that are definitely currency
    is_currency =
      (String.contains?(key_str, "balance") and not is_count) or
        String.contains?(key_str, "cents") or
        (String.contains?(key_str, "value") and not is_count) or
        String.contains?(key_str, "cost") or
        String.contains?(key_str, "debit") or
        String.contains?(key_str, "credit") or
        (String.contains?(key_str, "amount") and not is_count) or
        String.contains?(key_str, "difference")

    if is_currency do
      # Format cents as currency
      pesos = div(value, 100)
      cents = rem(value, 100)
      "#{pesos}.#{String.pad_leading(Integer.to_string(cents), 2, "0")} MXN"
    else
      # Format as plain number
      "#{value}"
    end
  end

  defp format_value(_key, value) when is_list(value) do
    "#{length(value)} items"
  end

  defp format_value(_key, value) do
    inspect(value)
  end
end
