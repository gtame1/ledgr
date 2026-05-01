defmodule Mix.Tasks.DiagnoseCogs do
  @moduledoc """
  Diagnose COGS (Cost of Goods Sold) calculation issues.

  This task helps identify why unit-level COGS might be incorrect in the Unit Economics report.

  Usage:
    mix diagnose_cogs                    # Run full diagnostics
    mix diagnose_cogs --product SKU      # Diagnose specific product
    mix diagnose_cogs --fix              # Fix duplicate entries (requires confirmation)
    mix diagnose_cogs --fix --yes        # Fix duplicate entries (no confirmation, runs until clean)
  """
  use Mix.Task

  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Domains.MrMunchMe.Orders.{Order, ProductVariant}
  alias Ledgr.Core.Accounting.JournalEntry
  alias Ledgr.Domains.MrMunchMe.Inventory
  alias Ledgr.Domains.MrMunchMe.Inventory.Recepies

  @shortdoc "Diagnose COGS calculation issues"

  def run(args) do
    # Start only the Repo without the full application (avoids web server startup)
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:ecto_sql)

    # Build repo config from DATABASE_URL (prod) or app config (dev)
    repo_config =
      case System.get_env("DATABASE_URL") do
        nil ->
          # Dev: load app config first
          Application.load(:ledgr)
          Application.get_env(:ledgr, Ledgr.Repos.MrMunchMe) || []

        url ->
          # Prod: use DATABASE_URL with SSL for Render
          [
            url: url,
            pool_size: 2,
            ssl: true,
            ssl_opts: [verify: :verify_none]
          ]
      end

    {:ok, _} = Ledgr.Repos.MrMunchMe.start_link(repo_config)
    Ledgr.Repo.put_active_repo(Ledgr.Repos.MrMunchMe)

    {opts, _, _} =
      OptionParser.parse(args, switches: [product: :string, fix: :boolean, yes: :boolean])

    IO.puts("\n🔍 COGS Diagnostic Report")
    IO.puts(String.duplicate("=", 70))
    IO.puts("")

    # 1. Check for duplicate journal entries
    duplicates = check_duplicate_entries()
    report_duplicates(duplicates)

    # 2. Check COGS per product
    product_sku = Keyword.get(opts, :product)

    if product_sku do
      diagnose_product_by_sku(product_sku)
    else
      diagnose_all_products()
    end

    # 3. If --fix flag is passed and duplicates found, offer to fix
    total_dupes = length(duplicates.in_prep) + length(duplicates.delivered)

    if Keyword.get(opts, :fix) && total_dupes > 0 do
      fix_duplicates(duplicates, Keyword.get(opts, :yes, false))
    end

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("Diagnostic complete.\n")
  end

  defp check_duplicate_entries do
    # Check for duplicate order_in_prep entries
    in_prep_dupes =
      from(je in JournalEntry,
        where: je.entry_type == "order_in_prep",
        where: like(je.reference, "Order #%"),
        group_by: je.reference,
        having: count(je.id) > 1,
        select: {je.reference, count(je.id)}
      )
      |> Repo.all()

    # Check for duplicate order_delivered entries
    delivered_dupes =
      from(je in JournalEntry,
        where: je.entry_type == "order_delivered",
        where: like(je.reference, "Order #%"),
        group_by: je.reference,
        having: count(je.id) > 1,
        select: {je.reference, count(je.id)}
      )
      |> Repo.all()

    %{in_prep: in_prep_dupes, delivered: delivered_dupes}
  end

  defp report_duplicates(duplicates) do
    IO.puts("📋 DUPLICATE JOURNAL ENTRIES CHECK")
    IO.puts(String.duplicate("-", 50))

    if duplicates.in_prep == [] and duplicates.delivered == [] do
      IO.puts("✅ No duplicate entries found\n")
    else
      if duplicates.in_prep != [] do
        IO.puts(
          "❌ Found #{length(duplicates.in_prep)} orders with duplicate 'order_in_prep' entries:"
        )

        Enum.each(duplicates.in_prep, fn {ref, count} ->
          IO.puts("   - #{ref}: #{count} entries")
        end)

        IO.puts("")
      end

      if duplicates.delivered != [] do
        IO.puts(
          "❌ Found #{length(duplicates.delivered)} orders with duplicate 'order_delivered' entries:"
        )

        Enum.each(duplicates.delivered, fn {ref, count} ->
          IO.puts("   - #{ref}: #{count} entries")
        end)

        IO.puts("")
      end

      IO.puts("⚠️  Duplicate entries are likely causing inflated COGS!")
      IO.puts("   Run with --fix flag to remove duplicates.\n")
    end
  end

  defp diagnose_all_products do
    IO.puts("\n📊 COGS BY VARIANT")
    IO.puts(String.duplicate("-", 50))

    # Get all variants with delivered orders
    variants =
      from(v in ProductVariant,
        join: p in assoc(v, :product),
        join: o in Order,
        on: o.variant_id == v.id,
        where: o.status == "delivered",
        distinct: true,
        preload: [product: p]
      )
      |> Repo.all()

    if variants == [] do
      IO.puts("No variants with delivered orders found.\n")
    else
      ingredient_costs = Inventory.ingredient_quick_infos()

      Enum.each(variants, fn variant ->
        diagnose_variant(variant, ingredient_costs)
      end)
    end
  end

  defp diagnose_product_by_sku(sku) do
    case Repo.get_by(ProductVariant, sku: sku) |> maybe_preload_product() do
      nil ->
        IO.puts("❌ Variant with SKU '#{sku}' not found\n")

      variant ->
        ingredient_costs = Inventory.ingredient_quick_infos()
        diagnose_variant(variant, ingredient_costs)
    end
  end

  defp maybe_preload_product(nil), do: nil
  defp maybe_preload_product(variant), do: Repo.preload(variant, :product)

  defp diagnose_variant(variant, ingredient_costs) do
    IO.puts("\n🍽️  #{variant.product.name} · #{variant.name} (#{variant.sku || "no SKU"})")
    IO.puts("   Price: #{format_currency(variant.price_cents)}")

    # Get delivered orders
    orders =
      from(o in Order,
        where: o.variant_id == ^variant.id and o.status == "delivered",
        select: o
      )
      |> Repo.all()

    units_sold = length(orders)
    IO.puts("   Units sold: #{units_sold}")

    if units_sold == 0 do
      IO.puts("   (No delivered orders)")
    else
      diagnose_variant_with_orders(variant, orders, ingredient_costs)
    end
  end

  defp diagnose_variant_with_orders(variant, orders, ingredient_costs) do
    units_sold = length(orders)

    # Calculate expected COGS from recipe
    recipe = Recepies.recipe_for_variant(variant)
    expected_cogs_per_unit = calculate_expected_cogs(recipe, ingredient_costs)

    # Get actual COGS from journal entries
    order_ids = Enum.map(orders, & &1.id)
    actual_total_cogs = get_actual_cogs_for_orders(order_ids)
    actual_cogs_per_unit = if units_sold > 0, do: div(actual_total_cogs, units_sold), else: 0

    # Report
    IO.puts("   Expected COGS per unit: #{format_currency(expected_cogs_per_unit)}")
    IO.puts("   Actual COGS per unit:   #{format_currency(actual_cogs_per_unit)}")
    IO.puts("   Actual total COGS:      #{format_currency(actual_total_cogs)}")

    if actual_cogs_per_unit > 0 and expected_cogs_per_unit > 0 do
      ratio = actual_cogs_per_unit / expected_cogs_per_unit

      if ratio > 1.5 do
        IO.puts(
          "   ⚠️  ACTUAL is #{Float.round(ratio, 1)}x EXPECTED - likely duplicates or data issue!"
        )
      else
        IO.puts("   ✅ COGS looks reasonable (#{Float.round(ratio, 2)}x expected)")
      end
    end

    # Check for entry count issues
    total_entries = count_cogs_entries_for_orders(order_ids)

    if total_entries > units_sold do
      IO.puts(
        "   ❌ Found #{total_entries} COGS entries for #{units_sold} orders - DUPLICATES DETECTED!"
      )
    end
  end

  defp calculate_expected_cogs(recipe, ingredient_costs) do
    Enum.reduce(recipe, 0, fn %{ingredient_code: code, quantity: qty}, acc ->
      case Map.get(ingredient_costs, code) do
        %{"avg_cost_cents" => cost} when is_integer(cost) and cost > 0 ->
          acc + trunc(cost * qty)

        _ ->
          acc
      end
    end)
  end

  defp get_actual_cogs_for_orders(order_ids) do
    if order_ids == [] do
      0
    else
      reference_patterns = Enum.map(order_ids, fn id -> "Order ##{id}" end)

      query =
        from(je in JournalEntry,
          join: jl in assoc(je, :journal_lines),
          join: acc in assoc(jl, :account),
          where: je.entry_type == "order_delivered" and acc.code == "5000"
        )

      [first_pattern | rest] = reference_patterns
      query = query |> where([je], je.reference == ^first_pattern)

      query =
        Enum.reduce(rest, query, fn pattern, q ->
          or_where(q, [je], je.reference == ^pattern)
        end)

      from([je, jl, acc] in query, select: sum(jl.debit_cents))
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end
    end
  end

  defp count_cogs_entries_for_orders(order_ids) do
    if order_ids == [] do
      0
    else
      reference_patterns = Enum.map(order_ids, fn id -> "Order ##{id}" end)

      query =
        from(je in JournalEntry,
          join: jl in assoc(je, :journal_lines),
          join: acc in assoc(jl, :account),
          where: je.entry_type == "order_delivered" and acc.code == "5000"
        )

      [first_pattern | rest] = reference_patterns
      query = query |> where([je], je.reference == ^first_pattern)

      query =
        Enum.reduce(rest, query, fn pattern, q ->
          or_where(q, [je], je.reference == ^pattern)
        end)

      # Use count(DISTINCT je.id) to count unique journal entries, not rows from the JOIN
      from([je, jl, acc] in query, select: fragment("count(DISTINCT ?)", je.id))
      |> Repo.one()
      |> case do
        nil -> 0
        count -> count
      end
    end
  end

  defp fix_duplicates(duplicates, auto_yes) do
    IO.puts("\n🔧 FIXING DUPLICATE ENTRIES")
    IO.puts(String.duplicate("-", 50))

    total_dupes = length(duplicates.in_prep) + length(duplicates.delivered)
    IO.puts("Found #{total_dupes} orders with duplicate entries.")
    IO.puts("This will keep the FIRST entry and delete subsequent duplicates.")

    should_proceed =
      if auto_yes do
        IO.puts("\n--yes flag passed, proceeding automatically...")
        true
      else
        IO.write("\nProceed? [y/N]: ")
        response = IO.gets("") |> String.trim() |> String.downcase()
        response == "y"
      end

    if should_proceed do
      # Fix in_prep duplicates
      Enum.each(duplicates.in_prep, fn {reference, _count} ->
        delete_duplicate_entries(reference, "order_in_prep")
      end)

      # Fix delivered duplicates
      Enum.each(duplicates.delivered, fn {reference, _count} ->
        delete_duplicate_entries(reference, "order_delivered")
      end)

      IO.puts("✅ First pass complete!")

      # Re-check for any remaining duplicates and fix them automatically
      remaining = check_duplicate_entries()
      remaining_count = length(remaining.in_prep) + length(remaining.delivered)

      if remaining_count > 0 do
        IO.puts("\n⚠️  Found #{remaining_count} more duplicates, fixing automatically...")
        fix_remaining_duplicates(remaining)
      else
        IO.puts("✅ All duplicates removed successfully!")
      end
    else
      IO.puts("Aborted. No changes made.")
    end
  end

  defp fix_remaining_duplicates(duplicates) do
    # Fix without prompting (already got permission)
    Enum.each(duplicates.in_prep, fn {reference, _count} ->
      delete_duplicate_entries(reference, "order_in_prep")
    end)

    Enum.each(duplicates.delivered, fn {reference, _count} ->
      delete_duplicate_entries(reference, "order_delivered")
    end)

    # Check again recursively until clean
    remaining = check_duplicate_entries()
    remaining_count = length(remaining.in_prep) + length(remaining.delivered)

    if remaining_count > 0 do
      IO.puts("   Found #{remaining_count} more, continuing...")
      fix_remaining_duplicates(remaining)
    else
      IO.puts("✅ All duplicates removed successfully!")
    end
  end

  defp delete_duplicate_entries(reference, entry_type) do
    # Get all entries for this order, ordered by id (oldest first)
    entries =
      from(je in JournalEntry,
        where: je.reference == ^reference and je.entry_type == ^entry_type,
        order_by: [asc: je.id],
        select: je
      )
      |> Repo.all()

    # Keep the first, delete the rest
    [_keep | to_delete] = entries

    Enum.each(to_delete, fn entry ->
      IO.puts("   Deleting duplicate #{entry_type} entry for #{reference} (id: #{entry.id})")
      Repo.delete!(entry)
    end)
  end

  defp format_currency(cents) when is_integer(cents) do
    pesos = div(cents, 100)
    centavos = rem(cents, 100)
    "$#{pesos}.#{String.pad_leading(Integer.to_string(centavos), 2, "0")}"
  end

  defp format_currency(_), do: "$0.00"
end
