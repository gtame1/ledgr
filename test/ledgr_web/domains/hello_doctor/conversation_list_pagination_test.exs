defmodule LedgrWeb.Domains.HelloDoctor.ConversationListPaginationTest do
  @moduledoc """
  The conversation index used to `Repo.all` every matching row and then preload
  `:patient` and `:consultations` onto all of them, so one request's peak
  memory grew with the table — the largest thing a user could trigger
  repeatedly on a 512 MB box.

  These pin that the page is bounded, that the total still counts the whole
  filtered set, and that paging carries the filters along (dropping them
  silently would show the operator the wrong rows under the right heading).
  """
  use LedgrWeb.ConnCase

  alias Ledgr.Domains.HelloDoctor.Conversations
  alias Ledgr.Repo

  @prefix "/app/hello-doctor"

  setup %{conn: conn} do
    Repo.put_active_repo(Ledgr.Repos.HelloDoctor)

    {:ok, user} =
      Ledgr.Core.Accounts.create_user(%{email: "op@hd.test", password: "password123!"})

    {:ok, conn: Phoenix.ConnTest.init_test_session(conn, %{"user_id:hello-doctor" => user.id})}
  end

  # `conversations.patient_id` is NOT NULL and the list page preloads
  # `:patient`, so every conversation gets its own patient — which is also
  # what makes the preload cost realistic.
  defp seed_conversations(n, attrs \\ %{}, prefix \\ "conv") do
    base = ~N[2026-06-01 12:00:00]
    at = fn i -> NaiveDateTime.add(base, i, :second) end
    key = fn i -> "#{prefix}_#{String.pad_leading("#{i}", 4, "0")}" end

    Repo.insert_all(
      "patients",
      for i <- 1..n do
        %{
          id: key.(i),
          full_name: "Patient #{i}",
          display_name: "P#{i}",
          phone: "+5215500#{String.pad_leading("#{i}", 5, "0")}",
          created_at: at.(i),
          updated_at: at.(i)
        }
      end
    )

    Repo.insert_all(
      "conversations",
      for i <- 1..n do
        Map.merge(
          %{
            id: key.(i),
            patient_id: key.(i),
            status: "active",
            funnel_stage: "triage",
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
      assert conn |> get(@prefix <> "/conversations") |> html_response(200) =~ "Conversations"
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
      assert html =~ "Next"
    end

    test "paging carries the active filters", %{conn: conn} do
      seed_conversations(60, %{status: "closed"})

      html =
        conn
        |> get(@prefix <> "/conversations", %{"status" => "closed"})
        |> html_response(200)

      # The Next link must keep status=closed, or page 2 shows a different set.
      assert html =~ "status=closed"
      assert html =~ "page=2"
    end

    test "a filtered total counts only matching rows" do
      seed_conversations(30, %{status: "active"}, "act")
      seed_conversations(10, %{status: "closed", funnel_stage: "completed"}, "clo")

      assert Conversations.paginate_conversations(status: "closed").total == 10
      assert Conversations.paginate_conversations(status: "active").total == 30
      assert Conversations.paginate_conversations([]).total == 40
    end
  end
end
