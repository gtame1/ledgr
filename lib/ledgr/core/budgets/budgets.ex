defmodule Ledgr.Core.Budgets do
  @moduledoc """
  Budget management: CRUD operations for monthly account budgets
  and budget-vs-actual variance reporting.
  """

  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Core.Budgets.Budget
  alias Ledgr.Core.Accounting.{Account, JournalEntry, JournalLine}

  # ------- CRUD -------

  def list_budgets(year, month) do
    from(b in Budget,
      where: b.year == ^year and b.month == ^month,
      preload: [:account],
      order_by: [asc: :account_id]
    )
    |> Repo.all()
  end

  def list_budgets_for_year(year) do
    from(b in Budget,
      where: b.year == ^year,
      preload: [:account],
      order_by: [asc: :month, asc: :account_id]
    )
    |> Repo.all()
  end

  def get_budget!(id), do: Repo.get!(Budget, id) |> Repo.preload(:account)

  def create_budget(attrs) do
    %Budget{}
    |> Budget.changeset(attrs)
    |> Repo.insert()
  end

  def update_budget(%Budget{} = budget, attrs) do
    budget
    |> Budget.changeset(attrs)
    |> Repo.update()
  end

  def delete_budget(%Budget{} = budget), do: Repo.delete(budget)

  def upsert_budget(attrs) do
    %Budget{}
    |> Budget.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:amount_cents, :updated_at]},
      conflict_target: [:account_id, :year, :month]
    )
  end

  @doc """
  Bulk upsert budgets for a given year/month.
  Expects a list of %{account_id: id, amount_cents: cents}.
  """
  def set_monthly_budgets(year, month, budget_items) do
    Enum.map(budget_items, fn item ->
      upsert_budget(Map.merge(item, %{year: year, month: month}))
    end)
  end

  # ------- BUDGET VS ACTUAL REPORT -------

  @doc """
  Generate a budget vs actual report for a single month.

  Returns a list of maps, one per budgeted account:
    %{
      account_code, account_name, account_type,
      budget_cents, actual_cents, variance_cents, variance_pct
    }

  Also includes summary totals for revenue, expenses, and net.
  """
  def budget_vs_actual(year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)

    budgets = list_budgets(year, month)

    if budgets == [] do
      %{
        year: year,
        month: month,
        line_items: [],
        total_budget_revenue_cents: 0,
        total_actual_revenue_cents: 0,
        total_budget_expense_cents: 0,
        total_actual_expense_cents: 0,
        net_budget_cents: 0,
        net_actual_cents: 0
      }
    else
      account_ids = Enum.map(budgets, & &1.account_id)

      # Get actual amounts from journal entries for the month
      actuals = actual_amounts_for_period(account_ids, start_date, end_date)

      line_items =
        Enum.map(budgets, fn budget ->
          actual = Map.get(actuals, budget.account_id, 0)
          # For expense accounts, actual = debit - credit (positive means spending)
          # For revenue accounts, actual = credit - debit (positive means earning)
          actual_amount = normalize_actual(actual, budget.account)
          variance = actual_amount - budget.amount_cents

          variance_pct =
            if budget.amount_cents > 0,
              do: Float.round(variance / budget.amount_cents * 100, 1),
              else: 0.0

          %{
            account_id: budget.account_id,
            account_code: budget.account.code,
            account_name: budget.account.name,
            account_type: budget.account.type,
            budget_cents: budget.amount_cents,
            actual_cents: actual_amount,
            variance_cents: variance,
            variance_pct: variance_pct
          }
        end)
        |> Enum.sort_by(& &1.account_code)

      # Summary totals
      {rev_items, exp_items} =
        Enum.split_with(line_items, fn li -> li.account_type == "revenue" end)

      total_budget_revenue = Enum.reduce(rev_items, 0, &(&1.budget_cents + &2))
      total_actual_revenue = Enum.reduce(rev_items, 0, &(&1.actual_cents + &2))
      total_budget_expense = Enum.reduce(exp_items, 0, &(&1.budget_cents + &2))
      total_actual_expense = Enum.reduce(exp_items, 0, &(&1.actual_cents + &2))

      %{
        year: year,
        month: month,
        line_items: line_items,
        total_budget_revenue_cents: total_budget_revenue,
        total_actual_revenue_cents: total_actual_revenue,
        total_budget_expense_cents: total_budget_expense,
        total_actual_expense_cents: total_actual_expense,
        net_budget_cents: total_budget_revenue - total_budget_expense,
        net_actual_cents: total_actual_revenue - total_actual_expense
      }
    end
  end

  @doc """
  Year-to-date budget vs actual through the given month.
  Aggregates monthly budgets and actuals from January through the target month.
  """
  def budget_vs_actual_ytd(year, through_month) do
    start_date = Date.new!(year, 1, 1)
    end_date = Date.end_of_month(Date.new!(year, through_month, 1))

    # Aggregate all budgets for the year up through the target month
    budgets_by_account =
      from(b in Budget,
        where: b.year == ^year and b.month <= ^through_month,
        group_by: b.account_id,
        select: {b.account_id, sum(b.amount_cents)}
      )
      |> Repo.all()
      |> Map.new()

    if budgets_by_account == %{} do
      %{
        year: year,
        through_month: through_month,
        line_items: [],
        total_budget_revenue_cents: 0,
        total_actual_revenue_cents: 0,
        total_budget_expense_cents: 0,
        total_actual_expense_cents: 0,
        net_budget_cents: 0,
        net_actual_cents: 0
      }
    else
      account_ids = Map.keys(budgets_by_account)
      accounts = Repo.all(from(a in Account, where: a.id in ^account_ids))
      accounts_map = Map.new(accounts, &{&1.id, &1})

      actuals = actual_amounts_for_period(account_ids, start_date, end_date)

      line_items =
        Enum.map(account_ids, fn acc_id ->
          account = Map.fetch!(accounts_map, acc_id)
          budget_total = Map.get(budgets_by_account, acc_id, 0)
          raw_actual = Map.get(actuals, acc_id, 0)
          actual_amount = normalize_actual(raw_actual, account)
          variance = actual_amount - budget_total

          variance_pct =
            if budget_total > 0,
              do: Float.round(variance / budget_total * 100, 1),
              else: 0.0

          %{
            account_id: acc_id,
            account_code: account.code,
            account_name: account.name,
            account_type: account.type,
            budget_cents: budget_total,
            actual_cents: actual_amount,
            variance_cents: variance,
            variance_pct: variance_pct
          }
        end)
        |> Enum.sort_by(& &1.account_code)

      {rev_items, exp_items} =
        Enum.split_with(line_items, fn li -> li.account_type == "revenue" end)

      %{
        year: year,
        through_month: through_month,
        line_items: line_items,
        total_budget_revenue_cents: Enum.reduce(rev_items, 0, &(&1.budget_cents + &2)),
        total_actual_revenue_cents: Enum.reduce(rev_items, 0, &(&1.actual_cents + &2)),
        total_budget_expense_cents: Enum.reduce(exp_items, 0, &(&1.budget_cents + &2)),
        total_actual_expense_cents: Enum.reduce(exp_items, 0, &(&1.actual_cents + &2)),
        net_budget_cents:
          Enum.reduce(rev_items, 0, &(&1.budget_cents + &2)) -
            Enum.reduce(exp_items, 0, &(&1.budget_cents + &2)),
        net_actual_cents:
          Enum.reduce(rev_items, 0, &(&1.actual_cents + &2)) -
            Enum.reduce(exp_items, 0, &(&1.actual_cents + &2))
      }
    end
  end

  # ------- PRIVATE HELPERS -------

  # Query actual debit/credit totals per account for a date range.
  # Returns %{account_id => net_cents} where net = debits - credits.
  defp actual_amounts_for_period(account_ids, start_date, end_date) do
    from(jl in JournalLine,
      join: je in JournalEntry,
      on: jl.journal_entry_id == je.id,
      where: jl.account_id in ^account_ids and je.date >= ^start_date and je.date <= ^end_date,
      group_by: jl.account_id,
      select: {jl.account_id, sum(jl.debit_cents) - sum(jl.credit_cents)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # For expense accounts: actual spending = debits - credits (positive is spending)
  # For revenue accounts: actual earning = credits - debits (flip sign so positive is earning)
  defp normalize_actual(net_debit_minus_credit, %Account{type: "revenue"}),
    do: -net_debit_minus_credit

  defp normalize_actual(net_debit_minus_credit, %Account{}),
    do: net_debit_minus_credit
end
