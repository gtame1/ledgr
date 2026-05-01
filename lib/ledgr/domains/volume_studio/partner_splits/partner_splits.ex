defmodule Ledgr.Domains.VolumeStudio.PartnerSplits do
  @moduledoc """
  Volume Studio partner splits — reusable named allocations of revenue/expenses
  across partners. Lines must sum to exactly 10,000 basis points (100%).

  Splits attach to:
    - subscriptions, consultations, space_rentals (via partner_split_id FK)
    - expenses (via the expense_partner_splits sidecar table — keeps the
      shared core expenses schema untouched)
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.PartnerSplits.{PartnerSplit, ExpensePartnerSplit}
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
  alias Ledgr.Domains.VolumeStudio.Consultations.Consultation
  alias Ledgr.Domains.VolumeStudio.Spaces.SpaceRental
  alias Ledgr.Core.Expenses.Expense
  alias Ledgr.Core.Partners.Partner

  # ── PartnerSplit CRUD ────────────────────────────────────────────────

  def list_partner_splits do
    from(s in PartnerSplit,
      where: is_nil(s.deleted_at),
      order_by: s.name,
      preload: [lines: :partner]
    )
    |> Repo.all()
  end

  def get_partner_split!(id) do
    from(s in PartnerSplit,
      where: s.id == ^id and is_nil(s.deleted_at),
      preload: [lines: :partner]
    )
    |> Repo.one!()
  end

  def change_partner_split(%PartnerSplit{} = split, attrs \\ %{}) do
    PartnerSplit.changeset(split, attrs)
  end

  def create_partner_split(attrs) do
    %PartnerSplit{}
    |> PartnerSplit.changeset(normalize_attrs(attrs))
    |> Repo.insert()
  end

  def update_partner_split(%PartnerSplit{} = split, attrs) do
    split
    |> Repo.preload(:lines)
    |> PartnerSplit.changeset(normalize_attrs(attrs))
    |> Repo.update()
  end

  def soft_delete_partner_split(%PartnerSplit{} = split) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    split
    |> Ecto.Changeset.change(deleted_at: now)
    |> Repo.update()
  end

  @doc "Returns [{name, id}] options for select inputs."
  def split_options do
    list_partner_splits()
    |> Enum.map(&{&1.name, &1.id})
  end

  # ── Expense sidecar ───────────────────────────────────────────────────

  @doc "Returns the partner_split_id assigned to the given expense, or nil."
  def split_id_for_expense(expense_id) when is_integer(expense_id) do
    from(eps in ExpensePartnerSplit,
      where: eps.expense_id == ^expense_id,
      select: eps.partner_split_id
    )
    |> Repo.one()
  end

  @doc """
  Sets or clears the partner split for an expense.

  Pass `nil` to clear the assignment.
  """
  def set_expense_split(expense_id, nil) when is_integer(expense_id) do
    from(eps in ExpensePartnerSplit, where: eps.expense_id == ^expense_id)
    |> Repo.delete_all()

    :ok
  end

  def set_expense_split(expense_id, partner_split_id)
      when is_integer(expense_id) and is_integer(partner_split_id) do
    %ExpensePartnerSplit{}
    |> ExpensePartnerSplit.changeset(%{
      expense_id: expense_id,
      partner_split_id: partner_split_id
    })
    |> Repo.insert(
      on_conflict: [set: [partner_split_id: partner_split_id, updated_at: DateTime.utc_now()]],
      conflict_target: :expense_id
    )
  end

  @doc "Bulk lookup of expense_id => partner_split_id, for a list of expense ids."
  def split_ids_for_expenses(expense_ids) when is_list(expense_ids) do
    from(eps in ExpensePartnerSplit,
      where: eps.expense_id in ^expense_ids,
      select: {eps.expense_id, eps.partner_split_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ── Partner breakdown report ─────────────────────────────────────────

  @doc """
  Returns a per-partner revenue/expense breakdown for the given period.

  Cash-basis approximation:
    - Subscriptions: paid_cents for subs whose inserted_at falls in the period.
    - Consultations: amount_cents for consultations paid in the period.
    - Rentals: paid_cents for rentals paid in the period.
    - Expenses: amount_cents for expenses dated in the period.

  Each splittable record contributes its amount to attached partners weighted
  by the split's basis points. Records without a split land in the
  `:unattributed` bucket.

  Returns:
    %{
      partners: [%{partner: %Partner{}, revenue_cents:, expense_cents:, net_cents:}],
      unattributed: %{revenue_cents:, expense_cents:, net_cents:},
      total: %{revenue_cents:, expense_cents:, net_cents:}
    }
  """
  def partner_breakdown(start_date, end_date)
      when is_struct(start_date, Date) and is_struct(end_date, Date) do
    splits_with_lines =
      from(s in PartnerSplit,
        where: is_nil(s.deleted_at),
        preload: [:lines]
      )
      |> Repo.all()
      |> Map.new(fn s -> {s.id, s.lines} end)

    partners =
      from(p in Partner, order_by: p.name)
      |> Repo.all()

    revenue_rows =
      collect_subscription_revenue(start_date, end_date) ++
        collect_consultation_revenue(start_date, end_date) ++
        collect_rental_revenue(start_date, end_date)

    expense_rows = collect_expense_rows(start_date, end_date)

    initial_partner_totals =
      Map.new(partners, fn p -> {p.id, %{revenue_cents: 0, expense_cents: 0}} end)

    initial_unattributed = %{revenue_cents: 0, expense_cents: 0}

    {by_partner, unattributed} =
      Enum.reduce(revenue_rows, {initial_partner_totals, initial_unattributed}, fn {split_id,
                                                                                    amount},
                                                                                   acc ->
        apportion(acc, split_id, amount, splits_with_lines, :revenue_cents)
      end)

    {by_partner, unattributed} =
      Enum.reduce(expense_rows, {by_partner, unattributed}, fn {split_id, amount}, acc ->
        apportion(acc, split_id, amount, splits_with_lines, :expense_cents)
      end)

    partner_results =
      Enum.map(partners, fn p ->
        totals = Map.get(by_partner, p.id, %{revenue_cents: 0, expense_cents: 0})

        %{
          partner: p,
          revenue_cents: totals.revenue_cents,
          expense_cents: totals.expense_cents,
          net_cents: totals.revenue_cents - totals.expense_cents
        }
      end)

    total_rev = Enum.sum(Enum.map(revenue_rows, &elem(&1, 1)))
    total_exp = Enum.sum(Enum.map(expense_rows, &elem(&1, 1)))

    %{
      partners: partner_results,
      unattributed: %{
        revenue_cents: unattributed.revenue_cents,
        expense_cents: unattributed.expense_cents,
        net_cents: unattributed.revenue_cents - unattributed.expense_cents
      },
      total: %{
        revenue_cents: total_rev,
        expense_cents: total_exp,
        net_cents: total_rev - total_exp
      }
    }
  end

  defp apportion({by_partner, unattributed}, nil, amount, _splits, key) do
    {by_partner, Map.update!(unattributed, key, &(&1 + amount))}
  end

  defp apportion({by_partner, unattributed}, split_id, amount, splits_with_lines, key) do
    case Map.get(splits_with_lines, split_id) do
      nil ->
        # Split was deleted — treat as unattributed
        {by_partner, Map.update!(unattributed, key, &(&1 + amount))}

      lines ->
        updated =
          Enum.reduce(lines, by_partner, fn line, acc ->
            share = div(amount * line.share_bps, 10_000)

            Map.update(acc, line.partner_id, %{revenue_cents: 0, expense_cents: 0}, fn p ->
              Map.update!(p, key, &(&1 + share))
            end)
          end)

        {updated, unattributed}
    end
  end

  defp collect_subscription_revenue(start_date, end_date) do
    from(s in Subscription,
      where: is_nil(s.deleted_at),
      where: fragment("?::date", s.inserted_at) >= ^start_date,
      where: fragment("?::date", s.inserted_at) <= ^end_date,
      where: s.paid_cents > 0,
      select: {s.partner_split_id, s.paid_cents}
    )
    |> Repo.all()
  end

  defp collect_consultation_revenue(start_date, end_date) do
    from(c in Consultation,
      where: is_nil(c.deleted_at),
      where: not is_nil(c.paid_at),
      where: c.paid_at >= ^start_date,
      where: c.paid_at <= ^end_date,
      select: {c.partner_split_id, c.amount_cents}
    )
    |> Repo.all()
  end

  defp collect_rental_revenue(start_date, end_date) do
    from(r in SpaceRental,
      where: is_nil(r.deleted_at),
      where: not is_nil(r.paid_at),
      where: r.paid_at >= ^start_date,
      where: r.paid_at <= ^end_date,
      where: r.paid_cents > 0,
      select: {r.partner_split_id, r.paid_cents}
    )
    |> Repo.all()
  end

  defp collect_expense_rows(start_date, end_date) do
    from(e in Expense,
      left_join: eps in ExpensePartnerSplit,
      on: eps.expense_id == e.id,
      where: e.date >= ^start_date,
      where: e.date <= ^end_date,
      select: {eps.partner_split_id, e.amount_cents}
    )
    |> Repo.all()
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  # Form posts lines as a map keyed by index ("0", "1", …). Convert to a list,
  # drop blank rows (no partner picked), and convert percentage → basis points.
  defp normalize_attrs(attrs) do
    case attrs do
      %{"lines" => lines} when is_map(lines) ->
        normalized =
          lines
          |> Enum.sort_by(fn {k, _} -> k end)
          |> Enum.map(fn {_, v} -> v end)
          |> Enum.reject(&blank_line?/1)
          |> Enum.map(&pct_to_bps/1)

        Map.put(attrs, "lines", normalized)

      _ ->
        attrs
    end
  end

  defp blank_line?(%{"partner_id" => p}) when p in [nil, ""], do: true
  defp blank_line?(%{partner_id: p}) when p in [nil, ""], do: true
  defp blank_line?(_), do: false

  # Accepts "share_pct" (decimal 0-100) and converts to share_bps.
  defp pct_to_bps(%{"share_pct" => pct} = line) when pct not in [nil, ""] do
    case Float.parse(to_string(pct)) do
      {f, _} -> Map.put(line, "share_bps", round(f * 100))
      :error -> line
    end
  end

  defp pct_to_bps(line), do: line
end
