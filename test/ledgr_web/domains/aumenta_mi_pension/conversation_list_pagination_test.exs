defmodule LedgrWeb.Domains.AumentaMiPension.ConversationListPaginationTest do
  @moduledoc """
  Mirrors the Hello Doctor pagination tests. The AMP conversation index had the
  same shape — `Repo.all` over every matching row, then `:customer` and
  `:consultations` preloaded onto all of them.
  """
  use LedgrWeb.ConnCase

  alias Ledgr.Domains.AumentaMiPension.Conversations
  alias Ledgr.Repo

  @prefix "/app/aumenta-mi-pension"

  setup %{conn: conn} do
    Repo.put_active_repo(Ledgr.Repos.AumentaMiPension)

    {:ok, user} =
      Ledgr.Core.Accounts.create_user(%{email: "op@amp.test", password: "password123!"})

    {:ok,
     conn: Phoenix.ConnTest.init_test_session(conn, %{"user_id:aumenta-mi-pension" => user.id})}
  end

  defp seed_conversations(n, attrs \\ %{}, prefix \\ "conv") do
    base = ~N[2026-06-01 12:00:00]
    at = fn i -> NaiveDateTime.add(base, i, :second) end
    key = fn i -> "#{prefix}_#{String.pad_leading("#{i}", 4, "0")}" end

    Repo.insert_all(
      "customers",
      for i <- 1..n do
        %{id: key.(i), full_name: "Cliente #{i}", display_name: "C#{i}", phone: "+52155#{i}"}
      end
    )

    Repo.insert_all(
      "conversations",
      for i <- 1..n do
        Map.merge(
          %{
            id: key.(i),
            customer_id: key.(i),
            status: "active",
            funnel_stage: "intake",
            created_at: at.(i),
            last_message_at: at.(i)
          },
          attrs
        )
      end
    )
  end

  describe "GET /conversations" do
    test "renders against an empty database", %{conn: conn} do
      assert conn |> get(@prefix <> "/conversations") |> html_response(200)
    end

    test "loads only one page of rows, but counts the whole set" do
      seed_conversations(120)

      page = Conversations.paginate_conversations([])

      assert length(page.entries) == 50
      assert page.total == 120
      assert page.total_pages == 3
    end

    test "page 2 shows different rows than page 1" do
      seed_conversations(120)

      ids = fn p ->
        [page: p]
        |> Conversations.paginate_conversations()
        |> Map.fetch!(:entries)
        |> Enum.map(& &1.id)
        |> MapSet.new()
      end

      assert MapSet.disjoint?(ids.(1), ids.(2))
    end

    test "the rendered page shows the pager and its true total", %{conn: conn} do
      seed_conversations(120)

      html = conn |> get(@prefix <> "/conversations") |> html_response(200)

      assert html =~ "of 120"
      assert html =~ "Page 1 of 3"
    end

    test "paging carries the active filters", %{conn: conn} do
      seed_conversations(60, %{status: "closed"})

      html =
        conn
        |> get(@prefix <> "/conversations", %{"status" => "closed"})
        |> html_response(200)

      assert html =~ "status=closed"
      assert html =~ "page=2"
    end

    test "a filtered total counts only matching rows" do
      seed_conversations(30, %{status: "active"}, "act")
      seed_conversations(10, %{status: "closed"}, "clo")

      assert Conversations.paginate_conversations(status: "closed").total == 10
      assert Conversations.paginate_conversations([]).total == 40
    end
  end
end
