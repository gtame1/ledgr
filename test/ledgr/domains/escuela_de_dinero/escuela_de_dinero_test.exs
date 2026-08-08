defmodule Ledgr.Domains.EscuelaDeDineroTest do
  use ExUnit.Case, async: true

  alias Ledgr.Domains.EscuelaDeDinero, as: Domain

  describe "operational-only contract" do
    test "declares no chart of accounts" do
      assert Domain.account_codes() == %{}
    end

    test "journal_entry_types/0 returns a list" do
      # Ledgr.Core.Accounting.JournalEntry flat-maps this across EVERY registered
      # domain, not just the active one. Returning a map or nil here would break
      # the transactions form on every other domain in the app.
      assert Domain.journal_entry_types() == []
      assert is_list(Domain.journal_entry_types())
    end

    test "no financial route is reachable" do
      paths = router_paths()
      prefix = Domain.path_prefix()

      for financial <- ~w(/reports/pnl /reports/balance_sheet /transactions /customers
                          /expenses /transfers /investments /account-transactions) do
        refute Enum.any?(paths, &(&1 == prefix <> financial)),
               "#{financial} is routed — this domain must have no financial pages"
      end
    end

    test "every route is a GET" do
      # The bot owns this database; Ledgr only reads it. A POST/PUT/DELETE route
      # appearing here means someone gave the admin a write path into bot-owned
      # data. Login/logout are the deliberate exception.
      prefix = Domain.path_prefix()

      writes =
        LedgrWeb.Router.__routes__()
        |> Enum.filter(&String.starts_with?(&1.path, prefix))
        |> Enum.reject(&(&1.path in ["#{prefix}/login", "#{prefix}/logout"]))
        |> Enum.reject(&(&1.verb == :get))
        |> Enum.map(&{&1.verb, &1.path})

      assert writes == []
    end
  end

  describe "navigation" do
    test "every menu label has a nav icon" do
      # Unmapped labels silently fall back to a generic "article" icon.
      icons = Domain.nav_icons()

      for group <- Domain.menu_items(), item <- group.items do
        assert Map.has_key?(icons, item.label),
               "#{item.label} has no entry in nav_icons/0"
      end
    end

    test "every menu path resolves to a real route" do
      # Implementing nav_icons/0 suppresses the shared Reports/Tools nav groups,
      # which makes menu_items/0 the SOLE source of navigation in this domain.
      # A typo here is an unreachable page, not a broken link somewhere else.
      paths = router_paths()

      for group <- Domain.menu_items(), item <- group.items do
        path = item.path |> String.split("?") |> hd()

        assert path in paths, "#{item.label} points at #{path}, which is not routed"
      end
    end

    test "nav_icons/0 is exported, which is what opts into the flat sidebar" do
      assert function_exported?(Domain, :nav_icons, 0)
      assert function_exported?(Domain, :sidebar_subtitle, 0)
    end
  end

  describe "theme" do
    test "carries every key the layout reads without a fallback" do
      theme = Domain.theme()

      for key <- [:sidebar_bg, :sidebar_text, :sidebar_hover, :primary, :primary_soft, :accent] do
        assert is_binary(theme[key]), "theme is missing #{key}"
      end
    end

    test "shadow_color is an RGB triple, not a hex" do
      # It is interpolated into rgba(); a leading '#' produces invalid CSS that
      # fails silently, taking every shadow on the domain with it.
      assert Domain.theme().shadow_color =~ ~r/^\d+, \d+, \d+$/
    end
  end

  defp router_paths do
    LedgrWeb.Router.__routes__() |> Enum.map(& &1.path)
  end
end
