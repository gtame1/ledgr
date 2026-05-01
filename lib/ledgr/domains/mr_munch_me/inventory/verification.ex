defmodule Ledgr.Domains.MrMunchMe.Inventory.Verification do
  @moduledoc """
  Verification functions to ensure inventory accounting integrity.
  """
  require Logger
  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.{Account, JournalEntry, JournalLine}
  alias Ledgr.Domains.MrMunchMe.Inventory.{Ingredient, InventoryItem, InventoryMovement}
  alias Ledgr.Domains.MrMunchMe.Orders.{Order, OrderPayment}

  @ingredients_account_code "1200"
  @packing_account_code "1210"
  @kitchen_account_code "1300"
  @wip_account_code "1220"
  @ar_code "1100"
  @customer_deposits_code "2200"
  @owners_equity_code "3000"
  @samples_gifts_code "6070"

  @doc """
  Verifies that inventory quantities match movements.
  Returns {:ok, []} if all good, {:error, issues} if problems found.
  Optimized: uses a single aggregation query instead of N+1 per-item queries.
  """
  def verify_inventory_quantities do
    # Check each inventory item with preloaded ingredient and location
    items =
      from(ii in InventoryItem,
        preload: [:ingredient, :location]
      )
      |> Repo.all()

    # Batch-calculate all quantities from movements in a single query
    calculated_map = calculate_all_quantities_from_movements()

    issues =
      Enum.reduce(items, [], fn item, acc ->
        calculated_qty = Map.get(calculated_map, {item.ingredient_id, item.location_id}, 0)

        if item.quantity_on_hand != calculated_qty do
          ingredient_name = item.ingredient.name || "Unknown"
          location_name = item.location.name || "Unknown"

          [
            "Inventory mismatch: #{ingredient_name} @ #{location_name} - " <>
              "System: #{item.quantity_on_hand}, Calculated: #{calculated_qty}"
            | acc
          ]
        else
          acc
        end
      end)

    if issues == [] do
      {:ok, %{checked_items: length(items), issues: []}}
    else
      {:error, issues}
    end
  end

  @doc """
  Verifies that WIP account is internally consistent.
  Reports the current WIP balance and number of orders in prep.
  """
  def verify_wip_balance do
    wip_account = Accounting.get_account_by_code!(@wip_account_code)

    # Get all debits and credits to WIP account (regardless of entry type)
    result =
      from(jl in JournalLine,
        where: jl.account_id == ^wip_account.id,
        select: %{
          total_debits: fragment("COALESCE(SUM(?), 0)", jl.debit_cents),
          total_credits: fragment("COALESCE(SUM(?), 0)", jl.credit_cents)
        }
      )
      |> Repo.one()

    debits = to_int(result && result.total_debits)
    credits = to_int(result && result.total_credits)

    wip_balance = debits - credits

    # Count orders currently in prep (have order_in_prep but no order_delivered)
    orders_in_prep = count_orders_in_prep()

    {:ok,
     %{
       wip_balance: wip_balance,
       total_debits: debits,
       total_credits: credits,
       orders_in_prep: orders_in_prep
     }}
  end

  defp count_orders_in_prep do
    # Get all orders that have order_in_prep entries
    in_prep_order_ids =
      from(je in JournalEntry,
        where: je.entry_type == "order_in_prep",
        select: je.reference
      )
      |> Repo.all()
      |> Enum.map(fn ref ->
        case Regex.run(~r/Order #(\d+)/, ref) do
          [_, order_id] -> String.to_integer(order_id)
          _ -> nil
        end
      end)
      |> Enum.filter(& &1)
      |> MapSet.new()

    # Get all orders that have order_delivered entries
    delivered_order_ids =
      from(je in JournalEntry,
        where: je.entry_type == "order_delivered",
        select: je.reference
      )
      |> Repo.all()
      |> Enum.map(fn ref ->
        case Regex.run(~r/Order #(\d+)/, ref) do
          [_, order_id] -> String.to_integer(order_id)
          _ -> nil
        end
      end)
      |> Enum.filter(& &1)
      |> MapSet.new()

    # Orders in prep = in_prep - delivered
    MapSet.difference(in_prep_order_ids, delivered_order_ids)
    |> MapSet.size()
  end

  @doc """
  Verifies that inventory cost values match journal entries for all inventory accounts:
  Ingredients (1200), Packing (1210), and Kitchen Equipment (1300).
  """
  def verify_inventory_cost_accounting do
    account_type_map = [
      {@ingredients_account_code, "ingredients", "Ingredients (1200)"},
      {@packing_account_code, "packing", "Packing (1210)"},
      {@kitchen_account_code, "kitchen", "Kitchen Equipment (1300)"}
    ]

    issues =
      Enum.reduce(account_type_map, [], fn {account_code, inv_type, label}, acc ->
        case Repo.get_by(Account, code: account_code) do
          # Account doesn't exist, skip
          nil ->
            acc

          account ->
            inventory_value = calculate_inventory_value_by_type(inv_type)
            account_balance = get_account_balance(account.id)

            if abs(inventory_value - account_balance) >= 100 do
              [
                "#{label} mismatch: Items=#{format_currency(inventory_value)}, Account=#{format_currency(account_balance)}, Difference=#{format_currency(abs(inventory_value - account_balance))}"
                | acc
              ]
            else
              acc
            end
        end
      end)

    if issues == [] do
      # Return totals for all accounts combined
      total_value = calculate_inventory_value()
      {:ok, %{inventory_value: total_value, issues: 0}}
    else
      {:error, Enum.reverse(issues)}
    end
  end

  @doc """
  Verifies that all order_in_prep entries have matching order_delivered entries
  (or orders are still in_prep).
  """
  def verify_order_wip_consistency do
    # Get all order_in_prep entries
    in_prep_orders =
      from(je in JournalEntry,
        where: je.entry_type == "order_in_prep",
        select: je.reference
      )
      |> Repo.all()
      |> Enum.map(fn ref ->
        case Regex.run(~r/Order #(\d+)/, ref) do
          [_, order_id] -> String.to_integer(order_id)
          _ -> nil
        end
      end)
      |> Enum.filter(& &1)

    # Check each order
    issues =
      Enum.reduce(in_prep_orders, [], fn order_id, acc ->
        # Check if order has been delivered
        has_delivered_entry =
          from(je in JournalEntry,
            where: je.entry_type == "order_delivered",
            where: je.reference == ^"Order ##{order_id}"
          )
          |> Repo.exists?()

        if has_delivered_entry do
          # Verify WIP was properly relieved
          wip_debit = get_wip_debit_for_order(order_id)
          wip_credit = get_wip_credit_for_order(order_id)

          if wip_debit != wip_credit do
            ["Order ##{order_id}: WIP debit (#{wip_debit}) != credit (#{wip_credit})" | acc]
          else
            acc
          end
        else
          # Order is still in_prep, which is fine
          acc
        end
      end)

    if issues == [] do
      {:ok, %{checked_orders: length(in_prep_orders), issues: []}}
    else
      {:error, issues}
    end
  end

  @doc """
  Verifies that all journal entries are balanced.
  Excludes year_end_close entries which are transfer entries that recognize accumulated income.
  Optimized: uses SQL-level aggregation instead of loading all entries into memory.
  """
  def verify_journal_entries_balanced do
    # Find unbalanced entries using SQL aggregation — no need to load all lines into memory
    unbalanced =
      from(jl in JournalLine,
        join: je in assoc(jl, :journal_entry),
        where: je.entry_type != "year_end_close",
        group_by: [je.id, je.entry_type],
        having: fragment("SUM(?) != SUM(?)", jl.debit_cents, jl.credit_cents),
        select: %{
          id: je.id,
          entry_type: je.entry_type,
          total_debits: fragment("SUM(?)", jl.debit_cents),
          total_credits: fragment("SUM(?)", jl.credit_cents)
        }
      )
      |> Repo.all()

    if unbalanced == [] do
      total_count =
        from(je in JournalEntry, where: je.entry_type != "year_end_close", select: count(je.id))
        |> Repo.one()

      {:ok, %{checked_entries: total_count, unbalanced: 0}}
    else
      issues =
        Enum.map(unbalanced, fn entry ->
          debits = to_int(entry.total_debits)
          credits = to_int(entry.total_credits)
          "Journal Entry ##{entry.id} (#{entry.entry_type}): Debits=#{debits}, Credits=#{credits}"
        end)

      {:error, issues}
    end
  end

  @doc """
  Verifies that withdrawal journal entries debit Owner's Drawings (3100) not Owner's Equity (3000).
  """
  def verify_withdrawal_accounts do
    case Repo.get_by(Account, code: @owners_equity_code) do
      nil ->
        {:ok, %{checked: 0, issues: 0}}

      owners_equity ->
        incorrect =
          from(jl in JournalLine,
            join: je in assoc(jl, :journal_entry),
            where:
              je.entry_type == "withdrawal" and
                jl.account_id == ^owners_equity.id and
                jl.debit_cents > 0,
            select: %{
              journal_entry_id: je.id,
              date: je.date,
              reference: je.reference,
              debit_cents: jl.debit_cents
            }
          )
          |> Repo.all()

        if incorrect == [] do
          {:ok, %{checked: "all withdrawals", issues: 0}}
        else
          total_cents = Enum.reduce(incorrect, 0, fn w, acc -> acc + w.debit_cents end)

          {:error,
           [
             "Found #{length(incorrect)} withdrawal(s) incorrectly debiting Owner's Equity (3000) instead of Owner's Drawings (3100). Total: #{format_currency(total_cents)}"
           ]}
        end
    end
  end

  @doc """
  Verifies that there are no duplicate COGS journal entries (same reference, multiple entries).
  """
  def verify_duplicate_cogs_entries do
    in_prep_dupes =
      from(je in JournalEntry,
        where: je.entry_type == "order_in_prep",
        where: like(je.reference, "Order #%"),
        group_by: je.reference,
        having: count(je.id) > 1,
        select: {je.reference, count(je.id)}
      )
      |> Repo.all()

    delivered_dupes =
      from(je in JournalEntry,
        where: je.entry_type == "order_delivered",
        where: like(je.reference, "Order #%"),
        group_by: je.reference,
        having: count(je.id) > 1,
        select: {je.reference, count(je.id)}
      )
      |> Repo.all()

    total_groups = length(in_prep_dupes) + length(delivered_dupes)

    if total_groups == 0 do
      {:ok, %{checked: "all order entries", duplicate_groups: 0}}
    else
      issues =
        Enum.map(in_prep_dupes, fn {ref, count} ->
          "Duplicate order_in_prep: #{ref} has #{count} entries (expected 1)"
        end) ++
          Enum.map(delivered_dupes, fn {ref, count} ->
            "Duplicate order_delivered: #{ref} has #{count} entries (expected 1)"
          end)

      {:error, issues}
    end
  end

  @doc """
  Verifies that there are no duplicate inventory movements (same ingredient, location,
  type, quantity, date, and source). Duplicates inflate inventory counts and costs.
  """
  def verify_duplicate_movements do
    dupes =
      from(m in InventoryMovement,
        group_by: [
          m.ingredient_id,
          m.from_location_id,
          m.to_location_id,
          m.movement_type,
          m.quantity,
          m.movement_date,
          m.source_type,
          m.source_id
        ],
        having: count(m.id) > 1,
        select: %{
          ingredient_id: m.ingredient_id,
          from_location_id: m.from_location_id,
          movement_type: m.movement_type,
          quantity: m.quantity,
          movement_date: m.movement_date,
          source_type: m.source_type,
          source_id: m.source_id,
          count: count(m.id)
        }
      )
      |> Repo.all()

    if dupes == [] do
      {:ok, %{checked: "all movements", duplicate_groups: 0}}
    else
      issues =
        Enum.map(dupes, fn d ->
          ingredient = Repo.get(Ingredient, d.ingredient_id)
          name = if ingredient, do: ingredient.name, else: "ID:#{d.ingredient_id}"

          "Duplicate #{d.movement_type}: #{name} qty=#{d.quantity} on #{d.movement_date} (#{d.count} copies, source: #{d.source_type}/#{d.source_id})"
        end)

      {:error, issues}
    end
  end

  @doc """
  Verifies that delivered gift orders have correct gift accounting (not sale-style).
  Checks both the original order_delivered entry AND any correction entries for the order.
  Optimized: batch-loads journal data instead of N+1 queries per gift order.
  """
  def verify_gift_order_accounting do
    samples_gifts = Repo.get_by(Account, code: @samples_gifts_code)

    gift_orders =
      from(o in Order,
        where: o.is_gift == true and o.status == "delivered",
        select: o
      )
      |> Repo.all()

    if gift_orders == [] or is_nil(samples_gifts) do
      {:ok, %{checked: length(gift_orders), issues: 0}}
    else
      # Build all references at once
      references = Enum.map(gift_orders, fn o -> "Order ##{o.id}" end)

      # Batch: find all order IDs that have at least one 6070 line in any of their journal entries
      orders_with_gift_lines =
        from(jl in JournalLine,
          join: je in assoc(jl, :journal_entry),
          where: je.reference in ^references,
          where: jl.account_id == ^samples_gifts.id,
          select: je.reference
        )
        |> Repo.all()
        |> Enum.map(fn ref ->
          case Regex.run(~r/Order #(\d+)/, ref) do
            [_, id_str] -> String.to_integer(id_str)
            _ -> nil
          end
        end)
        |> Enum.filter(& &1)
        |> MapSet.new()

      # Also check which gift orders have ANY journal entries at all
      orders_with_entries =
        from(je in JournalEntry,
          where: je.reference in ^references,
          select: je.reference
        )
        |> Repo.all()
        |> Enum.map(fn ref ->
          case Regex.run(~r/Order #(\d+)/, ref) do
            [_, id_str] -> String.to_integer(id_str)
            _ -> nil
          end
        end)
        |> Enum.filter(& &1)
        |> MapSet.new()

      affected =
        Enum.reduce(gift_orders, [], fn order, acc ->
          has_entries = MapSet.member?(orders_with_entries, order.id)
          has_gift_line = MapSet.member?(orders_with_gift_lines, order.id)

          if !has_entries or has_gift_line do
            acc
          else
            [order.id | acc]
          end
        end)

      if affected == [] do
        {:ok, %{checked: length(gift_orders), issues: 0}}
      else
        {:error,
         [
           "Found #{length(affected)} delivered gift order(s) with sale-style accounting instead of gift accounting: Order(s) ##{Enum.join(Enum.reverse(affected), ", #")}"
         ]}
      end
    end
  end

  @doc """
  Verifies that no inventory movements have $0 cost when they shouldn't.
  Only flags movements with quantity > 0 (zero-quantity movements legitimately have $0 cost).
  """
  def verify_movement_costs do
    zero_cost_movements =
      from(m in InventoryMovement,
        where: m.movement_type in ["usage", "write_off"],
        where: m.total_cost_cents == 0 or m.unit_cost_cents == 0,
        where: m.quantity > 0,
        where: not is_nil(m.from_location_id),
        select: count(m.id)
      )
      |> Repo.one()

    total_checked =
      from(m in InventoryMovement,
        where: m.movement_type in ["usage", "write_off"],
        where: not is_nil(m.from_location_id),
        select: count(m.id)
      )
      |> Repo.one()

    count = to_int(zero_cost_movements)
    total = to_int(total_checked)

    if count == 0 do
      {:ok, %{checked: total, zero_cost: 0}}
    else
      {:error,
       [
         "Found #{count} of #{total} usage/write-off movement(s) with $0 cost that may need backfilling"
       ]}
    end
  end

  @doc """
  Runs all verification checks and returns a report.
  Optimized: runs checks concurrently using Task.async for ~3-4x speedup.
  """
  def run_all_checks do
    checks = [
      {:inventory_quantities, &verify_inventory_quantities/0},
      {:inventory_cost_accounting, &verify_inventory_cost_accounting/0},
      {:movement_costs, &verify_movement_costs/0},
      {:duplicate_movements, &verify_duplicate_movements/0},
      {:wip_balance, &verify_wip_balance/0},
      {:order_wip_consistency, &verify_order_wip_consistency/0},
      {:journal_entries_balanced, &verify_journal_entries_balanced/0},
      {:duplicate_cogs_entries, &verify_duplicate_cogs_entries/0},
      {:withdrawal_accounts, &verify_withdrawal_accounts/0},
      {:gift_order_accounting, &verify_gift_order_accounting/0},
      {:ar_balance, &verify_ar_balance/0},
      {:customer_deposits, &verify_customer_deposits/0}
    ]

    checks
    |> Enum.map(fn {name, fun} ->
      task = Task.async(fn -> {name, fun.()} end)
      {name, task}
    end)
    |> Enum.map(fn {_name, task} -> Task.await(task, 30_000) end)
    |> Map.new()
  end

  @doc """
  Verifies that the GL AR balance per order matches expected AR (order total minus all payments).
  """
  def verify_ar_balance do
    ar_account = Repo.get_by(Account, code: @ar_code)

    if is_nil(ar_account) do
      {:error, ["Accounts Receivable account (#{@ar_code}) not found"]}
    else
      orders =
        from(o in Order,
          where: o.status == "delivered" and o.is_gift == false,
          preload: [variant: :product, order_payments: []]
        )
        |> Repo.all()

      if orders == [] do
        {:ok, %{checked_orders: 0, issues: 0}}
      else
        ar_by_order = get_gl_balance_by_order(ar_account.id)

        issues =
          Enum.reduce(orders, [], fn order, acc ->
            {product_total, shipping} = Ledgr.Domains.MrMunchMe.Orders.order_total_cents(order)
            order_total = product_total + shipping

            # Use customer_amount_cents for split payments — the partner portion
            # credits a partner payable account, not AR, so it must be excluded.
            total_paid =
              Enum.reduce(order.order_payments, 0, fn p, sum ->
                sum + (p.customer_amount_cents || p.amount_cents || 0)
              end)

            expected_ar = max(order_total - total_paid, 0)
            gl_ar = Map.get(ar_by_order, order.id, 0)

            if expected_ar != gl_ar do
              diff = expected_ar - gl_ar

              [
                "Order ##{order.id}: Expected AR=#{format_currency(expected_ar)}, " <>
                  "GL AR=#{format_currency(gl_ar)}, Difference=#{format_currency(diff)}"
                | acc
              ]
            else
              acc
            end
          end)

        if issues == [] do
          {:ok, %{checked_orders: length(orders), issues: 0}}
        else
          {:error, Enum.reverse(issues)}
        end
      end
    end
  end

  @doc """
  Verifies that Customer Deposits (2200) balance is correct per order.
  For delivered orders, deposits should have been transferred to AR (balance = 0).
  For non-delivered orders, deposits should still be in 2200.
  """
  def verify_customer_deposits do
    customer_deposits_account = Repo.get_by(Account, code: @customer_deposits_code)

    if is_nil(customer_deposits_account) do
      {:error, ["Customer Deposits account (#{@customer_deposits_code}) not found"]}
    else
      deposit_totals =
        from(p in OrderPayment,
          where: p.is_deposit == true,
          group_by: p.order_id,
          select:
            {p.order_id, sum(fragment("COALESCE(?, ?)", p.customer_amount_cents, p.amount_cents))}
        )
        |> Repo.all()
        |> Map.new()

      order_ids = Map.keys(deposit_totals)

      if order_ids == [] do
        {:ok, %{checked_orders: 0, issues: 0}}
      else
        orders =
          from(o in Order, where: o.id in ^order_ids)
          |> Repo.all()

        gl_deposits_by_order = get_gl_liability_balance_by_order(customer_deposits_account.id)

        issues =
          Enum.reduce(orders, [], fn order, acc ->
            deposit_paid = Map.get(deposit_totals, order.id, 0)
            gl_deposits = Map.get(gl_deposits_by_order, order.id, 0)

            expected =
              if order.status == "delivered" do
                0
              else
                deposit_paid
              end

            if gl_deposits != expected do
              [
                "Order ##{order.id} (#{order.status}): Expected deposits balance=#{format_currency(expected)}, " <>
                  "GL shows=#{format_currency(gl_deposits)}"
                | acc
              ]
            else
              acc
            end
          end)

        if issues == [] do
          {:ok, %{checked_orders: length(orders), issues: 0}}
        else
          {:error, Enum.reverse(issues)}
        end
      end
    end
  end

  # ── Private helpers for AR / Customer Deposits checks ──────────────────

  # Returns %{order_id => net_balance} where net_balance = debits − credits
  # for an asset account (e.g. AR 1100). Aggregates across ALL entry types
  # that reference "Order #N" (delivery entries, payment entries, corrections).
  # Optimized: uses SQL-level aggregation via regexp extraction.
  defp get_gl_balance_by_order(account_id) do
    # SQLite/Postgres-compatible: group by reference, aggregate debits/credits in SQL
    from(jl in JournalLine,
      join: je in assoc(jl, :journal_entry),
      where: jl.account_id == ^account_id,
      where: like(je.reference, "Order #%"),
      group_by: je.reference,
      select:
        {je.reference, fragment("SUM(?)", jl.debit_cents), fragment("SUM(?)", jl.credit_cents)}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {reference, debits, credits}, acc ->
      case Regex.run(~r/Order #(\d+)/, reference) do
        [_, id_str] ->
          order_id = String.to_integer(id_str)
          balance = to_int(debits) - to_int(credits)
          Map.update(acc, order_id, balance, &(&1 + balance))

        _ ->
          acc
      end
    end)
  end

  # Returns %{order_id => net_balance} where net_balance = credits − debits
  # for a liability account (e.g. Customer Deposits 2200).
  # Optimized: uses SQL-level aggregation.
  defp get_gl_liability_balance_by_order(account_id) do
    from(jl in JournalLine,
      join: je in assoc(jl, :journal_entry),
      where: jl.account_id == ^account_id,
      where: like(je.reference, "Order #%"),
      group_by: je.reference,
      select:
        {je.reference, fragment("SUM(?)", jl.debit_cents), fragment("SUM(?)", jl.credit_cents)}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {reference, debits, credits}, acc ->
      case Regex.run(~r/Order #(\d+)/, reference) do
        [_, id_str] ->
          order_id = String.to_integer(id_str)
          balance = to_int(credits) - to_int(debits)
          Map.update(acc, order_id, balance, &(&1 + balance))

        _ ->
          acc
      end
    end)
  end

  # ── Shared helper functions ─────────────────────────────────────────────

  # Batch version: calculates quantities for ALL ingredient×location combos in a single query set
  # Returns %{{ingredient_id, location_id} => quantity}
  defp calculate_all_quantities_from_movements do
    # Purchases (incoming to a location)
    purchases =
      from(m in InventoryMovement,
        where: m.movement_type == "purchase",
        where: not is_nil(m.to_location_id),
        group_by: [m.ingredient_id, m.to_location_id],
        select: {m.ingredient_id, m.to_location_id, fragment("COALESCE(SUM(?), 0)", m.quantity)}
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn {ing_id, loc_id, qty}, acc ->
        Map.update(acc, {ing_id, loc_id}, to_int(qty), &(&1 + to_int(qty)))
      end)

    # Usages & write-offs (outgoing from a location)
    usages =
      from(m in InventoryMovement,
        where: m.movement_type in ["usage", "write_off"],
        where: not is_nil(m.from_location_id),
        group_by: [m.ingredient_id, m.from_location_id],
        select: {m.ingredient_id, m.from_location_id, fragment("COALESCE(SUM(?), 0)", m.quantity)}
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn {ing_id, loc_id, qty}, acc ->
        Map.update(acc, {ing_id, loc_id}, to_int(qty), &(&1 + to_int(qty)))
      end)

    # Transfers in (incoming to a location)
    transfers_in =
      from(m in InventoryMovement,
        where: m.movement_type == "transfer",
        where: not is_nil(m.to_location_id),
        group_by: [m.ingredient_id, m.to_location_id],
        select: {m.ingredient_id, m.to_location_id, fragment("COALESCE(SUM(?), 0)", m.quantity)}
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn {ing_id, loc_id, qty}, acc ->
        Map.update(acc, {ing_id, loc_id}, to_int(qty), &(&1 + to_int(qty)))
      end)

    # Transfers out (outgoing from a location)
    transfers_out =
      from(m in InventoryMovement,
        where: m.movement_type == "transfer",
        where: not is_nil(m.from_location_id),
        group_by: [m.ingredient_id, m.from_location_id],
        select: {m.ingredient_id, m.from_location_id, fragment("COALESCE(SUM(?), 0)", m.quantity)}
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn {ing_id, loc_id, qty}, acc ->
        Map.update(acc, {ing_id, loc_id}, to_int(qty), &(&1 + to_int(qty)))
      end)

    # Merge all maps: purchases + transfers_in - usages - transfers_out
    all_keys =
      [purchases, usages, transfers_in, transfers_out]
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()

    Map.new(all_keys, fn key ->
      qty =
        Map.get(purchases, key, 0) + Map.get(transfers_in, key, 0) -
          Map.get(usages, key, 0) - Map.get(transfers_out, key, 0)

      {key, qty}
    end)
  end

  def calculate_quantity_from_movements(ingredient_id, location_id) do
    purchases =
      from(m in InventoryMovement,
        where: m.ingredient_id == ^ingredient_id,
        where: m.to_location_id == ^location_id,
        where: m.movement_type == "purchase",
        select: fragment("COALESCE(SUM(?), 0)", m.quantity)
      )
      |> Repo.one()
      |> to_int()

    usages =
      from(m in InventoryMovement,
        where: m.ingredient_id == ^ingredient_id,
        where: m.from_location_id == ^location_id,
        where: m.movement_type in ["usage", "write_off"],
        select: fragment("COALESCE(SUM(?), 0)", m.quantity)
      )
      |> Repo.one()
      |> to_int()

    transfers_in =
      from(m in InventoryMovement,
        where: m.ingredient_id == ^ingredient_id,
        where: m.to_location_id == ^location_id,
        where: m.movement_type == "transfer",
        select: fragment("COALESCE(SUM(?), 0)", m.quantity)
      )
      |> Repo.one()
      |> to_int()

    transfers_out =
      from(m in InventoryMovement,
        where: m.ingredient_id == ^ingredient_id,
        where: m.from_location_id == ^location_id,
        where: m.movement_type == "transfer",
        select: fragment("COALESCE(SUM(?), 0)", m.quantity)
      )
      |> Repo.one()
      |> to_int()

    purchases + transfers_in - usages - transfers_out
  end

  defp get_account_balance(account_id) do
    result =
      from(jl in JournalLine,
        where: jl.account_id == ^account_id,
        select: %{
          total_debits: fragment("COALESCE(SUM(?), 0)", jl.debit_cents),
          total_credits: fragment("COALESCE(SUM(?), 0)", jl.credit_cents)
        }
      )
      |> Repo.one()

    to_int(result && result.total_debits) - to_int(result && result.total_credits)
  end

  defp get_wip_debit_for_order(order_id) do
    reference = "Order ##{order_id}"
    wip_account = Accounting.get_account_by_code!(@wip_account_code)

    from(je in JournalEntry,
      join: jl in assoc(je, :journal_lines),
      where: je.entry_type == "order_in_prep",
      where: je.reference == ^reference,
      where: jl.account_id == ^wip_account.id,
      where: jl.debit_cents > 0,
      select: jl.debit_cents,
      limit: 1
    )
    |> Repo.one() || 0
  end

  defp get_wip_credit_for_order(order_id) do
    reference = "Order ##{order_id}"
    wip_account = Accounting.get_account_by_code!(@wip_account_code)

    from(je in JournalEntry,
      join: jl in assoc(je, :journal_lines),
      where: je.entry_type == "order_delivered",
      where: je.reference == ^reference,
      where: jl.account_id == ^wip_account.id,
      where: jl.credit_cents > 0,
      select: jl.credit_cents,
      limit: 1
    )
    |> Repo.one() || 0
  end

  # Calculates the total inventory value from InventoryItem records (qty × avg_cost)
  defp calculate_inventory_value do
    from(ii in InventoryItem,
      select:
        fragment(
          "COALESCE(SUM(? * ?), 0)",
          ii.quantity_on_hand,
          ii.avg_cost_per_unit_cents
        )
    )
    |> Repo.one()
    |> to_int()
  end

  # Calculates inventory value filtered by ingredient inventory_type
  defp calculate_inventory_value_by_type(inventory_type) do
    from(ii in InventoryItem,
      join: i in Ingredient,
      on: ii.ingredient_id == i.id,
      where: i.inventory_type == ^inventory_type,
      select:
        fragment(
          "COALESCE(SUM(? * ?), 0)",
          ii.quantity_on_hand,
          ii.avg_cost_per_unit_cents
        )
    )
    |> Repo.one()
    |> to_int()
  end

  # Converts a value to integer (handles Decimal, nil, and integer types)
  defp to_int(nil), do: 0
  defp to_int(val) when is_integer(val), do: val
  defp to_int(%Decimal{} = val), do: Decimal.to_integer(val)

  # Helper function to format cents as currency
  defp format_currency(cents) when is_integer(cents) do
    abs_cents = abs(cents)
    pesos = div(abs_cents, 100)
    cents_remainder = rem(abs_cents, 100)
    sign = if cents < 0, do: "-", else: ""
    "#{sign}#{pesos}.#{String.pad_leading(Integer.to_string(cents_remainder), 2, "0")} MXN"
  end
end
