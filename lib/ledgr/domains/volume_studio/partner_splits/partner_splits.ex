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

  # ── Helpers ──────────────────────────────────────────────────────────

  defp normalize_attrs(attrs) do
    case attrs do
      %{"lines" => lines} when is_map(lines) ->
        Map.put(attrs, "lines", lines |> Enum.sort_by(fn {k, _} -> k end) |> Enum.map(fn {_, v} -> v end))

      _ ->
        attrs
    end
  end
end
