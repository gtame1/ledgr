defmodule Ledgr.Domains.CasaTame.Categories do
  import Ecto.Query, warn: false
  alias Ledgr.Repo

  alias Ledgr.Domains.CasaTame.Categories.ExpenseCategory
  alias Ledgr.Domains.CasaTame.Categories.IncomeCategory

  # ── Expense Categories ──────────────────────────────────────────

  def list_expense_categories do
    from(c in ExpenseCategory,
      where: is_nil(c.parent_id),
      preload: [children: ^from(ch in ExpenseCategory, order_by: ch.name)],
      order_by: c.name
    )
    |> Repo.all()
  end

  @doc "Returns flat list of `{\"Parent > Child\", id}` for select dropdowns."
  def list_flat_expense_categories do
    parents = list_expense_categories()

    Enum.flat_map(parents, fn parent ->
      parent_option = {parent.name, parent.id}

      child_options =
        Enum.map(parent.children, fn child ->
          {"#{parent.name} > #{child.name}", child.id}
        end)

      [parent_option | child_options]
    end)
  end

  def get_expense_category!(id) do
    ExpenseCategory
    |> Repo.get!(id)
    |> Repo.preload(:children)
  end

  def change_expense_category(%ExpenseCategory{} = cat, attrs \\ %{}) do
    ExpenseCategory.changeset(cat, attrs)
  end

  def create_expense_category(attrs) do
    %ExpenseCategory{}
    |> ExpenseCategory.changeset(attrs)
    |> Repo.insert()
  end

  def update_expense_category(%ExpenseCategory{} = cat, attrs) do
    cat
    |> ExpenseCategory.changeset(attrs)
    |> Repo.update()
  end

  def delete_expense_category(%ExpenseCategory{} = cat) do
    Repo.delete(cat)
  end

  @doc "Returns parent categories as select options `[{name, id}]`."
  def parent_category_options do
    from(c in ExpenseCategory,
      where: is_nil(c.parent_id),
      order_by: c.name,
      select: {c.name, c.id}
    )
    |> Repo.all()
  end

  # ── Income Categories ───────────────────────────────────────────

  def list_income_categories do
    from(c in IncomeCategory, order_by: c.name)
    |> Repo.all()
  end

  def income_category_options do
    list_income_categories()
    |> Enum.map(&{&1.name, &1.id})
  end

  def get_income_category!(id), do: Repo.get!(IncomeCategory, id)
end
