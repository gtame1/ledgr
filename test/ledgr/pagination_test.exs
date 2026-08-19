defmodule Ledgr.PaginationTest do
  @moduledoc """
  Pins the behaviour the conversation index pages depend on: a bounded page,
  an accurate total, and clamping rather than an empty list when the page
  number is out of range.
  """
  use Ledgr.DataCase, async: true

  import Ecto.Query
  import Ledgr.Domains.MrMunchMe.OrdersFixtures

  alias Ledgr.Domains.MrMunchMe.Orders.Product
  alias Ledgr.Pagination

  defp seed(n) do
    for i <- 1..n, do: product_fixture(%{name: "Product #{String.pad_leading("#{i}", 3, "0")}"})
  end

  defp query, do: from(p in Product, order_by: [asc: p.name])

  describe "paginate/2" do
    test "returns only one page of rows and the full total" do
      seed(12)

      page = Pagination.paginate(query(), page: 1, page_size: 5)

      assert length(page.entries) == 5
      assert page.total == 12
      assert page.total_pages == 3
      assert page.page == 1
    end

    test "the last page holds the remainder" do
      seed(12)

      page = Pagination.paginate(query(), page: 3, page_size: 5)

      assert length(page.entries) == 2
      assert page.page == 3
    end

    test "pages do not overlap and together cover every row" do
      seed(12)

      names =
        for p <- 1..3,
            row <- Pagination.paginate(query(), page: p, page_size: 5).entries,
            do: row.name

      assert length(names) == 12
      assert length(Enum.uniq(names)) == 12
    end

    test "accepts a page number straight from params as a string" do
      seed(12)

      assert Pagination.paginate(query(), page: "2", page_size: 5).page == 2
    end

    test "clamps a page past the end to the last page rather than returning nothing" do
      seed(12)

      page = Pagination.paginate(query(), page: 99, page_size: 5)

      assert page.page == 3
      assert length(page.entries) == 2
    end

    test "clamps junk and zero to the first page" do
      seed(3)

      for bad <- ["not-a-number", "0", "-4", nil, 0, -1] do
        assert Pagination.paginate(query(), page: bad, page_size: 5).page == 1
      end
    end

    test "an empty table yields one empty page, not zero pages" do
      page = Pagination.paginate(query(), page: 1, page_size: 5)

      assert page.entries == []
      assert page.total == 0
      assert page.total_pages == 1
      assert Pagination.range(page) == {0, 0}
    end

    test "caps page_size so a crafted URL cannot ask for the whole table" do
      seed(3)

      assert Pagination.paginate(query(), page_size: 10_000).page_size == 200
    end

    test "counts correctly through a grouped query" do
      # Escuela de Dinero's conversation list groups by conversation to count
      # messages. Repo.aggregate on such a query raises unless it is wrapped
      # in a subquery, which is what paginate/2 does.
      seed(4)

      grouped = from(p in Product, group_by: p.id, select: %{id: p.id, n: count(p.id)})

      page = Pagination.paginate(grouped, page: 1, page_size: 3)

      assert page.total == 4
      assert length(page.entries) == 3
    end
  end

  describe "range/1" do
    test "reports the 1-based span shown on the page" do
      seed(12)

      assert Pagination.range(Pagination.paginate(query(), page: 1, page_size: 5)) == {1, 5}
      assert Pagination.range(Pagination.paginate(query(), page: 3, page_size: 5)) == {11, 12}
    end
  end
end
