defmodule Mix.Tasks.FixGiftOrderAccounting do
  @moduledoc """
  Fixes accounting entries for orders that were delivered as regular sales
  but later marked as gifts (is_gift = true).

  For each affected order, this task:
  1. Finds the original `order_delivered` journal entry
  2. Creates a correcting entry that reverses all original lines (swap Dr/Cr)
  3. Adds gift expense lines: Dr Samples & Gifts (6070), Cr WIP (1220)
  4. If the order had payments, reclassifies them as gift contributions:
     - Reverses the AR/Deposit credit from each payment entry
     - Credits Other Income - Gift Contributions (4100) instead

  Usage:
    mix fix_gift_order_accounting           # Dry run - shows what would be fixed
    mix fix_gift_order_accounting --fix     # Actually applies the corrections
  """

  use Mix.Task
  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.{JournalEntry, JournalLine, Account}
  alias Ledgr.Domains.MrMunchMe.Orders.Order

  @shortdoc "Fix accounting for delivered orders retroactively marked as gifts"

  @wip_code "1220"
  @ar_code "1100"
  @customer_deposits_code "2200"
  @samples_gifts_code "6070"
  @gift_contributions_code "4100"

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

    fix_mode = "--fix" in args

    IO.puts("\n=== Fix Gift Order Accounting ===\n")

    # Get required accounts
    wip = get_account!(@wip_code)
    ar = get_account!(@ar_code)
    customer_deposits = get_account!(@customer_deposits_code)
    samples_gifts = get_account!(@samples_gifts_code)
    gift_contributions = get_account!(@gift_contributions_code)

    # Find delivered orders marked as gifts that have sale-style journal entries
    affected_orders = find_affected_orders()

    if Enum.empty?(affected_orders) do
      IO.puts("✅ No gift orders with incorrect accounting entries found.")
      IO.puts("   All delivered gift orders already have correct accounting.")
    else
      IO.puts("Found #{length(affected_orders)} delivered gift order(s) with sale-style accounting:\n")

      for {order, entry, lines, payment_entries} <- affected_orders do
        print_order_details(order, entry, lines, payment_entries)
      end

      if fix_mode do
        IO.puts("\nApplying corrections...\n")

        results =
          Enum.map(affected_orders, fn {order, _entry, lines, payment_entries} ->
            apply_correction(order, lines, payment_entries, wip, ar, customer_deposits, samples_gifts, gift_contributions)
          end)

        successes = Enum.count(results, &match?({:ok, _}, &1))
        failures = Enum.count(results, &match?({:error, _}, &1))

        IO.puts("\n=== Summary ===")
        IO.puts("✅ #{successes} order(s) corrected successfully")

        if failures > 0 do
          IO.puts("❌ #{failures} order(s) failed")
        end
      else
        IO.puts("\nThis is a DRY RUN. To apply the corrections, run:")
        IO.puts("  mix fix_gift_order_accounting --fix")
      end
    end

    IO.puts("")
  end

  # Find delivered orders where is_gift=true that have a sale-style order_delivered entry
  # (i.e., the entry has lines touching Sales 4000 or COGS 5000, not Samples & Gifts 6070)
  # Also fetches associated payment journal entries for reclassification
  defp find_affected_orders do
    samples_gifts = get_account!(@samples_gifts_code)

    # Get all delivered gift orders
    gift_orders =
      from(o in Order,
        where: o.is_gift == true and o.status == "delivered",
        select: o
      )
      |> Repo.all()

    # For each, find the order_delivered entry and check if it's sale-style
    Enum.reduce(gift_orders, [], fn order, acc ->
      reference = "Order ##{order.id}"

      entry =
        from(je in JournalEntry,
          where: je.entry_type == "order_delivered" and je.reference == ^reference,
          limit: 1
        )
        |> Repo.one()

      case entry do
        nil ->
          # No delivery entry exists — nothing to fix
          acc

        entry ->
          lines =
            from(jl in JournalLine,
              where: jl.journal_entry_id == ^entry.id,
              preload: [:account]
            )
            |> Repo.all()

          # Check if this entry uses Samples & Gifts (6070) — if so, it's already correct
          has_gift_line = Enum.any?(lines, fn l -> l.account_id == samples_gifts.id end)

          if has_gift_line do
            # Already has gift accounting — skip
            acc
          else
            # Also find payment journal entries for this order
            payment_entries = find_payment_entries(order.id)
            [{order, entry, lines, payment_entries} | acc]
          end
      end
    end)
    |> Enum.reverse()
  end

  # Find all order_payment journal entries for a given order
  # Returns list of {entry, lines} tuples
  defp find_payment_entries(order_id) do
    # Payment entries have reference like "Order #<id> payment #<payment_id>"
    reference_prefix = "Order ##{order_id} payment #%"

    entries =
      from(je in JournalEntry,
        where: je.entry_type == "order_payment" and like(je.reference, ^reference_prefix)
      )
      |> Repo.all()

    Enum.map(entries, fn entry ->
      lines =
        from(jl in JournalLine,
          where: jl.journal_entry_id == ^entry.id,
          preload: [:account]
        )
        |> Repo.all()

      {entry, lines}
    end)
  end

  defp print_order_details(order, entry, lines, payment_entries) do
    IO.puts("  Order ##{order.id} (delivered)")
    IO.puts("    Delivery Entry ##{entry.id} (#{entry.date}): #{entry.description}")

    for line <- lines do
      account_info = "#{line.account.code} #{line.account.name}"

      if line.debit_cents > 0 do
        IO.puts("      Dr #{account_info}: $#{format_cents(line.debit_cents)}")
      end

      if line.credit_cents > 0 do
        IO.puts("      Cr #{account_info}: $#{format_cents(line.credit_cents)}")
      end
    end

    if Enum.empty?(payment_entries) do
      IO.puts("    💰 No payments to reclassify")
    else
      IO.puts("    💰 #{length(payment_entries)} payment entry(ies) to reclassify:")

      for {pentry, plines} <- payment_entries do
        IO.puts("      Payment Entry ##{pentry.id} (#{pentry.date}): #{pentry.description}")

        for line <- plines do
          account_info = "#{line.account.code} #{line.account.name}"

          if line.debit_cents > 0 do
            IO.puts("        Dr #{account_info}: $#{format_cents(line.debit_cents)}")
          end

          if line.credit_cents > 0 do
            IO.puts("        Cr #{account_info}: $#{format_cents(line.credit_cents)}")
          end
        end
      end
    end

    IO.puts("")
  end

  defp apply_correction(order, original_lines, payment_entries, wip, ar, customer_deposits, samples_gifts, gift_contributions) do
    # === PART 1: Reverse the delivery entry and add gift expense ===

    # Step 1: Reverse all original delivery lines (swap debits and credits)
    reversal_lines =
      Enum.map(original_lines, fn line ->
        %{
          account_id: line.account_id,
          debit_cents: line.credit_cents,
          credit_cents: line.debit_cents,
          description: "Reversal: #{line.description || "line for order ##{order.id}"}"
        }
      end)

    # Step 2: Find the WIP credit amount from original (this is the production cost)
    cost_cents =
      Enum.reduce(original_lines, 0, fn line, acc ->
        if line.account_id == wip.id and line.credit_cents > 0 do
          acc + line.credit_cents
        else
          acc
        end
      end)

    # Step 3: Add gift expense lines (Dr 6070, Cr WIP)
    gift_lines =
      if cost_cents > 0 do
        [
          %{
            account_id: samples_gifts.id,
            debit_cents: cost_cents,
            credit_cents: 0,
            description: "Samples & Gifts expense for gift order ##{order.id}"
          },
          %{
            account_id: wip.id,
            debit_cents: 0,
            credit_cents: cost_cents,
            description: "Relieve WIP for gift order ##{order.id}"
          }
        ]
      else
        []
      end

    # === PART 2: Reclassify payments as gift contributions ===
    #
    # Payment entries originally recorded:
    #   Dr Cash / Cr AR (1100)       — for regular payments
    #   Dr Cash / Cr Deposits (2200) — for deposit payments
    #
    # The cash side is correct (money was received and stays).
    # But since we're reversing the delivery entry (which debited AR / transferred deposits),
    # AR or Deposits would be left with an incorrect credit balance.
    #
    # Fix: reclassify the AR/Deposit credits to Other Income (4100).
    # For each payment entry, find lines that credited AR or Deposits and create
    # offsetting entries:
    #   Dr AR (1100) or Deposits (2200) — reverse the original credit
    #   Cr Other Income (4100)          — reclassify as gift contribution

    payment_reclassification_lines =
      Enum.flat_map(payment_entries, fn {_pentry, plines} ->
        Enum.flat_map(plines, fn line ->
          cond do
            # Line credits AR — reclassify to gift contributions
            line.account_id == ar.id and line.credit_cents > 0 ->
              [
                %{
                  account_id: ar.id,
                  debit_cents: line.credit_cents,
                  credit_cents: 0,
                  description: "Reverse AR credit from payment for gift order ##{order.id}"
                },
                %{
                  account_id: gift_contributions.id,
                  debit_cents: 0,
                  credit_cents: line.credit_cents,
                  description: "Reclassify payment as gift contribution for order ##{order.id}"
                }
              ]

            # Line credits Customer Deposits — reclassify to gift contributions
            line.account_id == customer_deposits.id and line.credit_cents > 0 ->
              [
                %{
                  account_id: customer_deposits.id,
                  debit_cents: line.credit_cents,
                  credit_cents: 0,
                  description: "Reverse deposit credit from payment for gift order ##{order.id}"
                },
                %{
                  account_id: gift_contributions.id,
                  debit_cents: 0,
                  credit_cents: line.credit_cents,
                  description: "Reclassify deposit as gift contribution for order ##{order.id}"
                }
              ]

            # Other lines (cash debits, partner payables, etc.) — leave as-is
            true ->
              []
          end
        end)
      end)

    all_lines = reversal_lines ++ gift_lines ++ payment_reclassification_lines

    entry_attrs = %{
      date: LedgrWeb.Helpers.DomainHelpers.today_mx(),
      entry_type: "other",
      reference: "Order ##{order.id}",
      description: "Correct order ##{order.id}: convert sale accounting to gift/sample"
    }

    case Accounting.create_journal_entry_with_lines(entry_attrs, all_lines) do
      {:ok, entry} ->
        IO.puts("  ✅ Order ##{order.id} — Correction entry ##{entry.id} created")

        for line <- all_lines do
          if line.debit_cents > 0 do
            IO.puts("      Dr $#{format_cents(line.debit_cents)} — #{line.description}")
          end

          if line.credit_cents > 0 do
            IO.puts("      Cr $#{format_cents(line.credit_cents)} — #{line.description}")
          end
        end

        {:ok, entry}

      {:error, changeset} ->
        IO.puts("  ❌ Order ##{order.id} — Failed to create correction entry:")
        IO.inspect(changeset.errors, label: "    Errors")
        {:error, changeset}
    end
  end

  defp get_account!(code) do
    case Repo.get_by(Account, code: code) do
      nil ->
        IO.puts("❌ Account #{code} not found! Run migrations first.")
        System.halt(1)

      account ->
        account
    end
  end

  defp format_cents(cents) when is_integer(cents) do
    :erlang.float_to_binary(cents / 100, decimals: 2)
  end

  defp format_cents(_), do: "0.00"
end
