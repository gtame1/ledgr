defmodule Ledgr.Domains.ViaxeDomainTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.Viaxe
  alias Ledgr.Core.Accounting

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)
    Ledgr.Domain.put_current(Ledgr.Domains.Viaxe)

    # Create Viaxe accounts needed for dashboard_metrics (P&L)
    viaxe_accounts = [
      %{code: "1000", name: "Cash",                  type: "asset",     normal_balance: "debit",  is_cash: true},
      %{code: "1100", name: "Commission Receivable",  type: "asset",     normal_balance: "debit",  is_cash: false},
      %{code: "2200", name: "Advance Commission",     type: "liability", normal_balance: "credit", is_cash: false},
      %{code: "3000", name: "Owner's Equity",         type: "equity",    normal_balance: "credit", is_cash: false},
      %{code: "3050", name: "Retained Earnings",      type: "equity",    normal_balance: "credit", is_cash: false},
      %{code: "3100", name: "Owner's Drawings",       type: "equity",    normal_balance: "debit",  is_cash: false},
      %{code: "4000", name: "Commission Revenue",     type: "revenue",   normal_balance: "credit", is_cash: false}
    ]

    Enum.each(viaxe_accounts, fn attrs ->
      case Accounting.get_account_by_code(attrs.code) do
        nil -> {:ok, _} = Accounting.create_account(attrs)
        _   -> :ok
      end
    end)

    :ok
  end

  describe "DomainConfig callbacks" do
    test "name/0" do
      assert Viaxe.name() == "Viaxe"
    end

    test "slug/0" do
      assert Viaxe.slug() == "viaxe"
    end

    test "path_prefix/0" do
      assert Viaxe.path_prefix() == "/app/viaxe"
    end

    test "public_home/0 returns nil" do
      assert is_nil(Viaxe.public_home())
    end

    test "logo/0 returns a string" do
      assert is_binary(Viaxe.logo())
    end

    test "theme/0 returns map with required keys" do
      theme = Viaxe.theme()
      assert is_map(theme)
      assert Map.has_key?(theme, :sidebar_bg)
      assert Map.has_key?(theme, :primary)
    end

    test "account_codes/0 returns required codes" do
      codes = Viaxe.account_codes()
      assert Map.has_key?(codes, :cash)
      assert Map.has_key?(codes, :commission_receivable)
      assert Map.has_key?(codes, :commission_revenue)
    end

    test "journal_entry_types/0 returns a non-empty list" do
      types = Viaxe.journal_entry_types()
      assert is_list(types)
      assert length(types) > 0
      type_strings = Enum.map(types, &elem(&1, 1))
      assert "booking_payment" in type_strings
      assert "booking_completed" in type_strings
    end

    test "menu_items/0 returns grouped menu items" do
      items = Viaxe.menu_items()
      assert is_list(items)
      assert Enum.all?(items, fn g -> Map.has_key?(g, :group) and Map.has_key?(g, :items) end)
    end

    test "seed_file/0 returns nil" do
      assert is_nil(Viaxe.seed_file())
    end

    test "has_active_dependencies?/1 returns false" do
      refute Viaxe.has_active_dependencies?(999)
    end
  end

  describe "RevenueHandler callbacks" do
    test "handle_status_change/2 with unknown status returns {:ok, nil}" do
      assert {:ok, nil} = Viaxe.handle_status_change(%{}, "some_status")
    end

    test "revenue_breakdown/2 returns empty list" do
      today = Date.utc_today()
      assert [] = Viaxe.revenue_breakdown(today, today)
    end

    test "cogs_breakdown/2 returns empty list" do
      today = Date.utc_today()
      assert [] = Viaxe.cogs_breakdown(today, today)
    end
  end

  describe "DashboardProvider callbacks" do
    test "dashboard_metrics/2 returns required keys" do
      today = Date.utc_today()
      result = Viaxe.dashboard_metrics(today, today)

      assert Map.has_key?(result, :pnl)
      assert Map.has_key?(result, :total_orders)
      assert Map.has_key?(result, :delivered_orders)
    end

    test "unit_economics/3 returns nil" do
      today = Date.utc_today()
      assert is_nil(Viaxe.unit_economics(1, today, today))
    end

    test "all_unit_economics/2 returns empty list" do
      today = Date.utc_today()
      assert [] = Viaxe.all_unit_economics(today, today)
    end

    test "product_select_options/0 returns empty list" do
      assert [] = Viaxe.product_select_options()
    end

    test "data_date_range/0 returns a tuple" do
      result = Viaxe.data_date_range()
      assert is_tuple(result)
    end

    test "verification_checks/0 returns empty map" do
      assert %{} = Viaxe.verification_checks()
    end

    test "delivered_order_count/2 returns 0" do
      today = Date.utc_today()
      assert 0 = Viaxe.delivered_order_count(today, today)
    end
  end
end
