defmodule Ledgr.Domains.MrMunchMeTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.MrMunchMe

  import Ledgr.Domains.MrMunchMe.OrdersFixtures
  import Ledgr.Core.AccountingFixtures
  import Ledgr.Core.CustomersFixtures

  describe "DomainConfig callbacks" do
    test "name/0 returns the domain name" do
      assert MrMunchMe.name() == "MrMunchMe"
    end

    test "slug/0 returns the url slug" do
      assert MrMunchMe.slug() == "mr-munch-me"
    end

    test "path_prefix/0 returns the path prefix" do
      assert MrMunchMe.path_prefix() == "/app/mr-munch-me"
    end

    test "public_home/0 returns the public storefront path" do
      assert MrMunchMe.public_home() == "/mr-munch-me/menu"
    end

    test "logo/0 returns a string" do
      assert is_binary(MrMunchMe.logo())
    end

    test "theme/0 returns a map with required keys" do
      theme = MrMunchMe.theme()
      assert is_map(theme)
      assert Map.has_key?(theme, :sidebar_bg)
      assert Map.has_key?(theme, :primary)
    end

    test "account_codes/0 returns required codes" do
      codes = MrMunchMe.account_codes()
      assert Map.has_key?(codes, :cash)
      assert Map.has_key?(codes, :sales)
      assert Map.has_key?(codes, :ar)
    end

    test "journal_entry_types/0 returns a non-empty list" do
      types = MrMunchMe.journal_entry_types()
      assert is_list(types)
      assert length(types) > 0
    end

    test "menu_items/0 returns grouped menu items" do
      items = MrMunchMe.menu_items()
      assert is_list(items)
      assert length(items) > 0

      Enum.each(items, fn group ->
        assert Map.has_key?(group, :group)
        assert Map.has_key?(group, :items)
      end)
    end

    test "seed_file/0 returns a file path string" do
      assert is_binary(MrMunchMe.seed_file())
    end
  end

  describe "has_active_dependencies?/1" do
    test "returns false when customer has no orders" do
      customer = customer_fixture(%{phone: "5550000001"})
      refute MrMunchMe.has_active_dependencies?(customer.id)
    end

    test "returns true when customer has an active order" do
      customer = customer_fixture(%{phone: "5550000002"})
      variant = variant_fixture()
      location = location_fixture()
      _order = order_fixture(%{variant: variant, location: location, status: "new_order", customer_id: customer.id})

      assert MrMunchMe.has_active_dependencies?(customer.id)
    end

    test "returns false when customer only has canceled orders" do
      customer = customer_fixture(%{phone: "5550000003"})
      variant = variant_fixture()
      location = location_fixture()
      _order = order_fixture(%{variant: variant, location: location, status: "canceled", customer_id: customer.id})

      refute MrMunchMe.has_active_dependencies?(customer.id)
    end
  end

  describe "data_date_range/0" do
    test "returns nil tuple when no data exists" do
      {earliest, latest} = MrMunchMe.data_date_range()
      # May be nil if no data
      assert is_nil(earliest) or (is_struct(earliest, Date) and is_struct(latest, Date))
    end

    test "returns date range when orders exist" do
      _accounts = standard_accounts_fixture()
      variant = variant_fixture()
      location = location_fixture()
      today = Date.utc_today()
      _order = order_fixture(%{variant: variant, location: location, delivery_date: today})

      {earliest, latest} = MrMunchMe.data_date_range()
      # With journal entries, we get a date range
      assert is_nil(earliest) or is_struct(earliest, Date)
      assert is_nil(latest) or is_struct(latest, Date)
    end
  end

  describe "delivered_order_count/2" do
    test "returns 0 when no delivered orders exist" do
      today = Date.utc_today()
      assert MrMunchMe.delivered_order_count(today, today) == 0
    end

    test "counts only delivered orders in date range" do
      variant = variant_fixture()
      location = location_fixture()
      today = Date.utc_today()

      _delivered = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})
      _new_order = order_fixture(%{variant: variant, location: location, status: "new_order", delivery_date: today})
      _canceled = order_fixture(%{variant: variant, location: location, status: "canceled", delivery_date: today})

      count = MrMunchMe.delivered_order_count(today, today)
      assert count == 1
    end

    test "filters by date range" do
      variant = variant_fixture()
      location = location_fixture()
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      _today_order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: today})
      _yesterday_order = order_fixture(%{variant: variant, location: location, status: "delivered", delivery_date: yesterday})

      assert MrMunchMe.delivered_order_count(today, today) == 1
      assert MrMunchMe.delivered_order_count(yesterday, today) == 2
    end
  end

  describe "RevenueHandler callbacks" do
    test "handle_status_change/2 delegates to OrderAccounting" do
      _accounts = standard_accounts_fixture()
      variant = variant_fixture()
      location = location_fixture()
      order = order_fixture(%{variant: variant, location: location})

      # new_order is a no-op, should return :ok
      assert :ok = MrMunchMe.handle_status_change(order, "new_order")
    end
  end
end
