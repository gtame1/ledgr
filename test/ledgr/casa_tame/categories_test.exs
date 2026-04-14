defmodule Ledgr.Domains.CasaTame.CategoriesTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.CasaTame.Categories
  alias Ledgr.Domains.CasaTame.Categories.{ExpenseCategory, IncomeCategory}

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.CasaTame)
    Ledgr.Domain.put_current(Ledgr.Domains.CasaTame)
    :ok
  end

  defp unique_name(prefix), do: "#{prefix} #{System.unique_integer([:positive])}"

  describe "expense categories" do
    test "create_expense_category/1 inserts a top-level category" do
      name = unique_name("Housing")
      assert {:ok, %ExpenseCategory{name: ^name, parent_id: nil}} =
               Categories.create_expense_category(%{name: name})
    end

    test "create_expense_category/1 requires :name" do
      assert {:error, changeset} = Categories.create_expense_category(%{})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "create_expense_category/1 supports a parent" do
      {:ok, parent} = Categories.create_expense_category(%{name: unique_name("Food")})

      {:ok, child} =
        Categories.create_expense_category(%{name: unique_name("Groceries"), parent_id: parent.id})

      assert child.parent_id == parent.id
    end

    test "list_expense_categories/0 returns only top-level, preloading children" do
      {:ok, p1} = Categories.create_expense_category(%{name: unique_name("Transport")})
      {:ok, _c1} = Categories.create_expense_category(%{name: unique_name("Gas"), parent_id: p1.id})

      results = Categories.list_expense_categories()

      parent = Enum.find(results, &(&1.id == p1.id))
      assert parent
      assert is_list(parent.children)
      assert length(parent.children) == 1
    end

    test "list_flat_expense_categories/0 flattens parent + child rows" do
      {:ok, parent} = Categories.create_expense_category(%{name: "Utilities #{System.unique_integer([:positive])}"})
      {:ok, child} = Categories.create_expense_category(%{name: "Water #{System.unique_integer([:positive])}", parent_id: parent.id})

      flat = Categories.list_flat_expense_categories()

      assert Enum.any?(flat, fn {label, id} -> label == parent.name and id == parent.id end)
      assert Enum.any?(flat, fn {label, id} -> label =~ "#{parent.name} > #{child.name}" and id == child.id end)
    end

    test "get_expense_category!/1 preloads children" do
      {:ok, parent} = Categories.create_expense_category(%{name: unique_name("Kids")})
      {:ok, _} = Categories.create_expense_category(%{name: unique_name("School"), parent_id: parent.id})

      loaded = Categories.get_expense_category!(parent.id)
      assert length(loaded.children) == 1
    end

    test "update_expense_category/2 updates the name" do
      {:ok, cat} = Categories.create_expense_category(%{name: unique_name("Original")})
      {:ok, updated} = Categories.update_expense_category(cat, %{name: "Renamed #{System.unique_integer([:positive])}"})
      assert updated.name != cat.name
    end

    test "delete_expense_category/1 removes the row" do
      {:ok, cat} = Categories.create_expense_category(%{name: unique_name("Temp")})
      assert {:ok, _} = Categories.delete_expense_category(cat)

      assert_raise Ecto.NoResultsError, fn ->
        Categories.get_expense_category!(cat.id)
      end
    end

    test "change_expense_category/2 returns a changeset" do
      cat = %ExpenseCategory{name: "X"}
      cs = Categories.change_expense_category(cat, %{name: "Y"})
      assert %Ecto.Changeset{} = cs
    end

    test "parent_category_options/0 returns only top-level as {name, id}" do
      {:ok, top} = Categories.create_expense_category(%{name: unique_name("Zzzz")})
      {:ok, _child} = Categories.create_expense_category(%{name: unique_name("SubZzzz"), parent_id: top.id})

      opts = Categories.parent_category_options()
      assert Enum.any?(opts, fn {name, id} -> id == top.id and name == top.name end)
      refute Enum.any?(opts, fn {_name, id} -> id == top.id and false end)
    end
  end

  describe "income categories" do
    test "list_income_categories/0 returns ordered rows" do
      {:ok, _} = Ledgr.Repo.insert(%IncomeCategory{name: unique_name("Zeta Income")})
      {:ok, _} = Ledgr.Repo.insert(%IncomeCategory{name: unique_name("Alpha Income")})

      names = Categories.list_income_categories() |> Enum.map(& &1.name)
      assert names == Enum.sort(names)
    end

    test "income_category_options/0 returns {name, id} tuples" do
      {:ok, cat} = Ledgr.Repo.insert(%IncomeCategory{name: unique_name("Freelance")})
      opts = Categories.income_category_options()
      assert Enum.any?(opts, fn {name, id} -> id == cat.id and name == cat.name end)
    end

    test "get_income_category!/1 returns the category" do
      {:ok, cat} = Ledgr.Repo.insert(%IncomeCategory{name: unique_name("Consulting")})
      assert Categories.get_income_category!(cat.id).id == cat.id
    end

    test "get_income_category!/1 raises for missing id" do
      assert_raise Ecto.NoResultsError, fn ->
        Categories.get_income_category!(-1)
      end
    end
  end
end
