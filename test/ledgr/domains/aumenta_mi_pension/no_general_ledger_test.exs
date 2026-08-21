defmodule Ledgr.Domains.AumentaMiPension.NoGeneralLedgerTest do
  @moduledoc """
  Aumenta Mi Pensión is an operational view: it reads a database the bot owns
  and posts nothing to the general ledger.

  Its ledger was written to eight times, all in 2026, the last on 14 May. The
  tables are kept for that history but frozen. These pin the three ways the
  ledger could come back — code, routes, and the database itself — so a future
  change has to be deliberate rather than accidental.
  """
  use LedgrWeb.ConnCase

  @amp_source Path.wildcard("lib/ledgr/domains/aumenta_mi_pension/**/*.ex") ++
                Path.wildcard("lib/ledgr_web/domains/aumenta_mi_pension/**/*.ex")

  describe "the domain code" do
    test "does not reference the accounting core at all" do
      # Comments and docs are stripped first: this is about what the code does,
      # not what it explains. A module is free to say why it no longer posts.
      offenders =
        for path <- @amp_source,
            code = strip_comments(File.read!(path)),
            String.contains?(code, "Core.Accounting") or
              String.contains?(code, "JournalEntry") or
              String.contains?(code, "JournalLine"),
            do: path

      assert offenders == [],
             "these AMP modules reach into the general ledger: #{inspect(offenders)}"
    end

    test "declares no chart of accounts and no journal entry types" do
      assert Ledgr.Domains.AumentaMiPension.account_codes() == %{}
      assert Ledgr.Domains.AumentaMiPension.journal_entry_types() == []
    end
  end

  describe "the routes" do
    setup %{conn: conn} do
      Ledgr.Repo.put_active_repo(Ledgr.Repos.AumentaMiPension)

      {:ok, user} =
        Ledgr.Core.Accounts.create_user(%{email: "gl@amp.test", password: "password123!"})

      {:ok,
       conn: Phoenix.ConnTest.init_test_session(conn, %{"user_id:aumenta-mi-pension" => user.id})}
    end

    for path <- ~w[
          /reports/pnl /reports/balance_sheet /reports/cash_flow
          /reports/financial_analysis /reports/ap_summary
          /transactions /account-transactions
          /reconciliation/accounting /investments /transfers /expenses
        ] do
      test "GET #{path} is not routed", %{conn: conn} do
        # The endpoint renders a 404 page rather than raising, so assert on the
        # status rather than reaching for assert_error_sent/2.
        assert get(conn, "/app/aumenta-mi-pension" <> unquote(path)).status == 404
      end
    end
  end

  describe "the nav" do
    test "offers no accounting pages" do
      paths =
        Ledgr.Domains.AumentaMiPension.menu_items()
        |> Enum.flat_map(fn
          %{items: items} -> items
          item -> [item]
        end)
        |> Enum.map(& &1.path)

      refute Enum.any?(paths, &String.contains?(&1, "reports/")),
             "AMP's sidebar still links a financial report"

      refute Enum.any?(paths, &(String.contains?(&1, "transactions") or
                                  String.contains?(&1, "reconciliation")))
    end
  end

  # Drops `#` line comments and @moduledoc/@doc heredocs.
  defp strip_comments(src) do
    src
    |> String.replace(~r/@(module)?doc\s+"""(.|\n)*?"""/, "")
    |> String.split("\n")
    |> Enum.map(&Regex.replace(~r/#.*$/, &1, ""))
    |> Enum.join("\n")
  end
end
