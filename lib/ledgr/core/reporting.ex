defmodule Ledgr.Core.Reporting do
  @moduledoc """
  Core financial reporting queries that work across all domains.
  Cash flow, P&L aggregation, etc.
  """

  import Ecto.Query, warn: false
  alias Ledgr.Repo

  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.{JournalEntry, JournalLine}

  @doc """
  Calculate cash flow for a date range.
  Returns cash inflows, outflows, net cash flow, and beginning/ending balances.

  Cash accounts are debit-normal assets:
  - Debit to cash = money coming IN (inflow)
  - Credit to cash = money going OUT (outflow)

  Internal transfers between cash accounts are excluded from
  inflow/outflow totals since they don't represent real cash movement.
  """
  def cash_flow(start_date, end_date) do
    # Get all cash accounts
    cash_accounts =
      from(a in Accounting.Account,
        where: a.is_cash == true
      )
      |> Repo.all()

    cash_account_ids = Enum.map(cash_accounts, & &1.id)

    # Beginning and ending cash balances
    beginning_balance_cents =
      cash_balance_as_of(cash_account_ids, Date.add(start_date, -1))

    ending_balance_cents =
      cash_balance_as_of(cash_account_ids, end_date)

    # Identify pure cash-to-cash journal entries (internal transfers that
    # don't represent real cash movement). A journal entry is cash-to-cash
    # when EVERY line in it touches a cash account.
    cash_to_cash_entry_ids = cash_to_cash_entry_ids(cash_account_ids, start_date, end_date)

    # Cash inflows = debits to cash accounts (money received)
    # Exclude pure cash-to-cash moves (they inflate both sides)
    cash_inflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.debit_cents > 0 and
            je.id not in ^cash_to_cash_entry_ids and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Cash outflows = credits to cash accounts (money paid out)
    cash_outflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.credit_cents > 0 and
            je.id not in ^cash_to_cash_entry_ids and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.credit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Net cash flow
    net_cash_flow_cents = cash_inflows_cents - cash_outflows_cents

    # Break down by category
    # Inflows: order payments, investments
    sales_inflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.debit_cents > 0 and
            je.entry_type == "order_payment" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    investment_inflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.debit_cents > 0 and
            je.entry_type == "investment" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.debit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Outflows: expenses, inventory purchases, withdrawals
    expense_outflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.credit_cents > 0 and
            je.entry_type in ["expense", "inventory_purchase"] and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.credit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    withdrawal_outflows_cents =
      from(je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        where:
          jl.account_id in ^cash_account_ids and
            jl.credit_cents > 0 and
            je.entry_type == "withdrawal" and
            je.date >= ^start_date and
            je.date <= ^end_date,
        select: sum(jl.credit_cents)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    other_inflows_cents = cash_inflows_cents - sales_inflows_cents - investment_inflows_cents

    other_outflows_cents =
      cash_outflows_cents - expense_outflows_cents - withdrawal_outflows_cents

    # IAS 7 / NIF B-2 Standard Classification:
    # Operating: sales receipts, operating expense payments, inventory purchases
    # Investing: currently minimal (equipment purchases would go here)
    # Financing: owner investments and withdrawals
    operating_inflows = sales_inflows_cents + other_inflows_cents
    operating_outflows = expense_outflows_cents + other_outflows_cents
    net_operating = operating_inflows - operating_outflows

    # Future: equipment purchases would be classified here
    net_investing = 0

    financing_inflows = investment_inflows_cents
    financing_outflows = withdrawal_outflows_cents
    net_financing = financing_inflows - financing_outflows

    %{
      period: %{start_date: start_date, end_date: end_date},
      beginning_balance_cents: beginning_balance_cents,
      ending_balance_cents: ending_balance_cents,
      cash_inflows_cents: cash_inflows_cents,
      cash_outflows_cents: cash_outflows_cents,
      net_cash_flow_cents: net_cash_flow_cents,
      # Standard IAS 7 classification
      operating: %{
        inflows_cents: operating_inflows,
        outflows_cents: operating_outflows,
        net_cents: net_operating
      },
      investing: %{
        inflows_cents: 0,
        outflows_cents: 0,
        net_cents: net_investing
      },
      financing: %{
        inflows_cents: financing_inflows,
        outflows_cents: financing_outflows,
        net_cents: net_financing
      },
      # Detailed sub-breakdown (backward compatible)
      breakdown: %{
        sales_inflows_cents: sales_inflows_cents,
        investment_inflows_cents: investment_inflows_cents,
        expense_outflows_cents: expense_outflows_cents,
        withdrawal_outflows_cents: withdrawal_outflows_cents,
        other_inflows_cents: other_inflows_cents,
        other_outflows_cents: other_outflows_cents
      }
    }
  end

  @doc """
  Financial analysis ratios for a period.

  Composes profit_and_loss/2, balance_sheet/1, and cash_flow/2 to compute:
  - Profitability ratios (margins, ROE)
  - Efficiency ratios (turnover, days, cash conversion cycle)
  - Leverage ratios (assets/equity, debt/equity)
  - Liquidity ratios (current ratio, quick ratio)
  - Business-specific metrics (cash runway, inventory coverage, revenue per order)

  Options (domain-specific data the caller provides):
    - :inventory_value_cents  (integer) current total inventory value
    - :delivered_order_count  (integer) orders delivered in the period
  """
  def financial_analysis(start_date, end_date, opts \\ []) do
    # 1) Gather base financial data (reuse existing functions)
    pnl = Accounting.profit_and_loss(start_date, end_date)
    bs = Accounting.balance_sheet(end_date)
    cf = cash_flow(start_date, end_date)

    # 2) Extract key P&L values
    revenue = pnl.total_revenue_cents
    cogs = pnl.total_cogs_cents
    gross_profit = pnl.gross_profit_cents
    operating_income = pnl.operating_income_cents
    net_income = pnl.net_income_cents
    total_opex = pnl.total_opex_cents

    # 3) Extract balance sheet values
    total_assets = bs.total_assets_cents
    total_liabilities = bs.total_liabilities_cents
    # Include current-period net income in equity (not yet closed to retained earnings)
    total_equity = bs.total_equity_cents + (bs.net_income_cents || 0)

    # 4) Extract account-level balances for specific ratios
    cash_balance = cf.ending_balance_cents
    ar_balance = find_account_balance(bs.assets, "1100")

    # Inventory: prefer actual inventory system value over GL balance
    # Note: Kitchen Equipment (1300) is a fixed asset, not working capital inventory
    inventory_gl =
      find_account_balance(bs.assets, "1200") +
        find_account_balance(bs.assets, "1210")

    inventory_value = Keyword.get(opts, :inventory_value_cents) || inventory_gl
    wip_balance = find_account_balance(bs.assets, "1220")

    # Current assets = cash + AR + inventory + WIP
    current_assets = cash_balance + ar_balance + inventory_value + wip_balance
    # Current liabilities = all liabilities (only Customer Deposits 2200 exists)
    current_liabilities = total_liabilities

    # 5) Period info
    period_days = Date.diff(end_date, start_date) + 1
    annualization_factor = if period_days > 0, do: 365.0 / period_days, else: 1.0
    delivered_order_count = Keyword.get(opts, :delivered_order_count, 0)

    # 6) Compute ratios

    # --- PROFITABILITY ---
    profitability = %{
      gross_margin_percent: safe_percent(gross_profit, revenue),
      operating_margin_percent: safe_percent(operating_income, revenue),
      net_margin_percent: safe_percent(net_income, revenue),
      roe_percent: safe_percent(net_income * annualization_factor, total_equity)
    }

    # --- EFFICIENCY ---
    asset_turnover = safe_divide(revenue, total_assets)
    inventory_turnover = safe_divide(cogs, inventory_value)
    days_inventory = safe_days(inventory_turnover)

    ar_turnover = safe_divide(revenue, ar_balance)
    avg_collection_period = safe_days(ar_turnover)

    ap_turnover = safe_divide(cogs, current_liabilities)
    days_payable = safe_days(ap_turnover)

    cash_conversion_cycle =
      if days_inventory && avg_collection_period && days_payable do
        Float.round(days_inventory + avg_collection_period - days_payable, 1)
      else
        nil
      end

    efficiency = %{
      asset_turnover: asset_turnover,
      inventory_turnover: inventory_turnover,
      days_inventory: days_inventory,
      ar_turnover: ar_turnover,
      avg_collection_period: avg_collection_period,
      ap_turnover: ap_turnover,
      days_payable: days_payable,
      cash_conversion_cycle: cash_conversion_cycle
    }

    # --- LEVERAGE ---
    leverage = %{
      assets_to_equity: safe_divide(total_assets, total_equity),
      debt_to_equity: safe_divide(total_liabilities, total_equity)
    }

    # --- LIQUIDITY ---
    liquidity = %{
      current_ratio: safe_divide(current_assets, current_liabilities),
      quick_ratio: safe_divide(current_assets - inventory_value, current_liabilities)
    }

    # --- BUSINESS OPERATIONS ---
    monthly_opex =
      if period_days > 0, do: round(total_opex * 30.0 / period_days), else: 0

    monthly_inv_purchases =
      if period_days > 0 do
        round(cf.breakdown.expense_outflows_cents * 30.0 / period_days)
      else
        0
      end

    bakery = %{
      cash_runway_months:
        if(monthly_opex > 0,
          do: Float.round(cash_balance / monthly_opex, 1),
          else: nil
        ),
      inventory_coverage_months:
        if(monthly_inv_purchases > 0,
          do: Float.round(cash_balance / monthly_inv_purchases, 1),
          else: nil
        ),
      revenue_per_order_cents:
        if(delivered_order_count > 0, do: div(revenue, delivered_order_count), else: nil),
      gross_profit_per_order_cents:
        if(delivered_order_count > 0, do: div(gross_profit, delivered_order_count), else: nil)
    }

    # --- RAW DATA (for template transparency) ---
    raw = %{
      revenue_cents: revenue,
      cogs_cents: cogs,
      gross_profit_cents: gross_profit,
      operating_income_cents: operating_income,
      net_income_cents: net_income,
      total_opex_cents: total_opex,
      total_assets_cents: total_assets,
      total_liabilities_cents: total_liabilities,
      total_equity_cents: total_equity,
      cash_balance_cents: cash_balance,
      ar_balance_cents: ar_balance,
      inventory_value_cents: inventory_value,
      wip_balance_cents: wip_balance,
      current_assets_cents: current_assets,
      current_liabilities_cents: current_liabilities,
      delivered_order_count: delivered_order_count,
      period_days: period_days
    }

    %{
      period: %{start_date: start_date, end_date: end_date},
      profitability: profitability,
      efficiency: efficiency,
      leverage: leverage,
      liquidity: liquidity,
      bakery: bakery,
      raw: raw
    }
  end

  # Find journal entry IDs where ALL lines touch cash accounts (pure cash-to-cash moves).
  # These entries just shuffle money between cash accounts and should be excluded from
  # inflow/outflow totals (they net to zero in the cash balance).
  #
  # Works by comparing each entry's total line count to the count of lines that hit cash.
  # If they match, every line in the entry is a cash account line → pure cash-to-cash.
  defp cash_to_cash_entry_ids(cash_account_ids, start_date, end_date) do
    from(je in JournalEntry,
      join: jl in JournalLine,
      on: jl.journal_entry_id == je.id,
      where: je.date >= ^start_date and je.date <= ^end_date,
      group_by: je.id,
      having:
        count(jl.id) ==
          sum(
            fragment(
              "CASE WHEN ? = ANY(?) THEN 1 ELSE 0 END",
              jl.account_id,
              ^cash_account_ids
            )
          ),
      select: je.id
    )
    |> Repo.all()
  end

  # Calculate total cash balance as of a given date.
  # Cash accounts are debit-normal: balance = sum(debits) - sum(credits).
  defp cash_balance_as_of(cash_account_ids, as_of_date) do
    from(jl in JournalLine,
      join: je in JournalEntry,
      on: jl.journal_entry_id == je.id,
      where:
        jl.account_id in ^cash_account_ids and
          je.date <= ^as_of_date,
      select: coalesce(sum(jl.debit_cents), 0) - coalesce(sum(jl.credit_cents), 0)
    )
    |> Repo.one()
    |> case do
      nil -> 0
      total -> total
    end
  end

  # Find sum of account balances in balance sheet list matching a code prefix
  defp find_account_balance(account_list, code_prefix) do
    account_list
    |> Enum.filter(fn %{account: acc} -> String.starts_with?(acc.code, code_prefix) end)
    |> Enum.reduce(0, fn %{amount_cents: amount}, sum -> sum + amount end)
  end

  # Safe division returning float, 0.0 on zero denominator
  defp safe_divide(_numerator, denominator) when denominator == 0, do: 0.0

  defp safe_divide(numerator, denominator) do
    Float.round(numerator * 1.0 / denominator, 2)
  end

  # Safe percentage: (numerator / denominator) * 100, rounded to 2 decimals
  defp safe_percent(_numerator, 0), do: 0.0

  defp safe_percent(numerator, denominator) do
    Float.round(numerator * 100.0 / denominator, 2)
  end

  # Convert turnover ratio to days (365 / turnover), nil if turnover is zero
  defp safe_days(turnover) when turnover > 0, do: Float.round(365.0 / turnover, 1)
  defp safe_days(_), do: nil
end
