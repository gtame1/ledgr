defmodule LedgrWeb.Domains.CasaTame.CategoryController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.CasaTame.Categories
  alias Ledgr.Domains.CasaTame.Categories.ExpenseCategory

  def index(conn, _params) do
    categories = Categories.list_expense_categories()
    render(conn, :index, categories: categories)
  end

  def new(conn, _params) do
    changeset = Categories.change_expense_category(%ExpenseCategory{})

    render(conn, :new,
      changeset: changeset,
      action: dp(conn, "/categories"),
      parent_options: Categories.parent_category_options()
    )
  end

  def create(conn, %{"expense_category" => attrs}) do
    case Categories.create_expense_category(attrs) do
      {:ok, _cat} ->
        conn |> put_flash(:info, "Category created.") |> redirect(to: dp(conn, "/categories"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new,
          changeset: changeset,
          action: dp(conn, "/categories"),
          parent_options: Categories.parent_category_options()
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    category = Categories.get_expense_category!(id)
    changeset = Categories.change_expense_category(category)

    render(conn, :edit,
      category: category,
      changeset: changeset,
      action: dp(conn, "/categories/#{category.id}"),
      parent_options: Categories.parent_category_options()
    )
  end

  def update(conn, %{"id" => id, "expense_category" => attrs}) do
    category = Categories.get_expense_category!(id)

    case Categories.update_expense_category(category, attrs) do
      {:ok, _cat} ->
        conn |> put_flash(:info, "Category updated.") |> redirect(to: dp(conn, "/categories"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit,
          category: category,
          changeset: changeset,
          action: dp(conn, "/categories/#{category.id}"),
          parent_options: Categories.parent_category_options()
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    category = Categories.get_expense_category!(id)

    case Categories.delete_expense_category(category) do
      {:ok, _} ->
        conn |> put_flash(:info, "Category deleted.") |> redirect(to: dp(conn, "/categories"))

      {:error, _} ->
        conn |> put_flash(:error, "Cannot delete category (may have associated expenses).") |> redirect(to: dp(conn, "/categories"))
    end
  end
end

defmodule LedgrWeb.Domains.CasaTame.CategoryHTML do
  use LedgrWeb, :html

  embed_templates "category_html/*"
end
