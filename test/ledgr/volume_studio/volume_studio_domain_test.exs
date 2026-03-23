defmodule Ledgr.Domains.VolumeStudioDomainTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.VolumeStudio

  import Ledgr.Domains.VolumeStudio.Fixtures

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.VolumeStudio)
    Ledgr.Domain.put_current(Ledgr.Domains.VolumeStudio)
    :ok
  end

  describe "DomainConfig callbacks" do
    test "name/0 returns the domain name" do
      assert VolumeStudio.name() == "Volume Studio"
    end

    test "slug/0 returns the url slug" do
      assert VolumeStudio.slug() == "volume-studio"
    end

    test "path_prefix/0 returns the path prefix" do
      assert VolumeStudio.path_prefix() == "/app/volume-studio"
    end

    test "public_home/0 returns nil (no public storefront)" do
      assert is_nil(VolumeStudio.public_home())
    end

    test "logo/0 returns a string" do
      assert is_binary(VolumeStudio.logo())
    end

    test "theme/0 returns a map with required keys" do
      theme = VolumeStudio.theme()
      assert is_map(theme)
      assert Map.has_key?(theme, :sidebar_bg)
      assert Map.has_key?(theme, :primary)
    end

    test "account_codes/0 returns required codes" do
      codes = VolumeStudio.account_codes()
      assert Map.has_key?(codes, :cash)
      assert Map.has_key?(codes, :subscription_revenue)
      assert Map.has_key?(codes, :deferred_subscription_revenue)
    end

    test "paid_to_account_options/0 returns a non-empty list" do
      options = VolumeStudio.paid_to_account_options()
      assert is_list(options)
      assert length(options) > 0
    end

    test "journal_entry_types/0 returns a list of tuples" do
      types = VolumeStudio.journal_entry_types()
      assert is_list(types)
      assert length(types) > 0
      assert Enum.all?(types, fn {label, type} -> is_binary(label) and is_binary(type) end)
    end

    test "menu_items/0 returns grouped menu items" do
      items = VolumeStudio.menu_items()
      assert is_list(items)
      assert Enum.all?(items, fn g -> Map.has_key?(g, :group) and Map.has_key?(g, :items) end)
    end

    test "seed_file/0 returns nil" do
      assert is_nil(VolumeStudio.seed_file())
    end

    test "has_active_dependencies?/1 always returns false" do
      refute VolumeStudio.has_active_dependencies?(999)
    end
  end

  describe "RevenueHandler callbacks" do
    test "handle_status_change/2 returns :ok" do
      assert :ok = VolumeStudio.handle_status_change(%{}, "any_status")
    end

    test "record_payment/1 returns :ok" do
      assert :ok = VolumeStudio.record_payment(%{})
    end

    test "revenue_breakdown/2 returns empty list" do
      today = Date.utc_today()
      assert [] = VolumeStudio.revenue_breakdown(today, today)
    end

    test "cogs_breakdown/2 returns empty list" do
      today = Date.utc_today()
      assert [] = VolumeStudio.cogs_breakdown(today, today)
    end
  end

  describe "DashboardProvider callbacks" do
    setup do
      vs_accounts_fixture()
      :ok
    end

    test "dashboard_metrics/2 returns required keys" do
      today = Date.utc_today()
      result = VolumeStudio.dashboard_metrics(today, today)

      assert Map.has_key?(result, :pnl)
      assert Map.has_key?(result, :upcoming_sessions)
      assert Map.has_key?(result, :active_subscriptions_count)
      assert Map.has_key?(result, :expiring_soon_count)
      assert Map.has_key?(result, :period_sessions_count)
      assert Map.has_key?(result, :sessions_by_status)
    end

    test "dashboard_metrics/2 counts active subscriptions" do
      plan = plan_fixture()
      _sub1 = subscription_fixture(%{plan: plan, status: "active"})
      _sub2 = subscription_fixture(%{plan: plan, status: "active"})
      _cancelled = subscription_fixture(%{plan: plan, status: "cancelled"})

      today = Date.utc_today()
      result = VolumeStudio.dashboard_metrics(today, today)

      assert result.active_subscriptions_count >= 2
    end

    test "dashboard_metrics/2 counts expiring soon subscriptions" do
      plan = plan_fixture()
      today = Date.utc_today()

      # Expiring within 30 days
      _expiring = subscription_fixture(%{
        plan: plan,
        status: "active",
        starts_on: today,
        ends_on: Date.add(today, 10)
      })

      result = VolumeStudio.dashboard_metrics(today, today)
      assert result.expiring_soon_count >= 1
    end

    test "unit_economics/3 returns nil" do
      today = Date.utc_today()
      assert is_nil(VolumeStudio.unit_economics(1, today, today))
    end

    test "all_unit_economics/2 returns empty list" do
      today = Date.utc_today()
      assert [] = VolumeStudio.all_unit_economics(today, today)
    end

    test "product_select_options/0 returns empty list" do
      assert [] = VolumeStudio.product_select_options()
    end

    test "data_date_range/0 returns a tuple" do
      result = VolumeStudio.data_date_range()
      assert is_tuple(result)
      {earliest, latest} = result
      assert is_nil(earliest) or is_struct(earliest, Date)
      assert is_nil(latest) or is_struct(latest, Date)
    end

    test "verification_checks/0 returns an empty map" do
      assert %{} = VolumeStudio.verification_checks()
    end

    test "delivered_order_count/2 always returns 0" do
      today = Date.utc_today()
      assert 0 = VolumeStudio.delivered_order_count(today, today)
    end
  end

  describe "on_customer_soft_delete/2" do
    test "soft-deletes customer subscriptions, bookings, consultations, and rentals" do
      _accounts = vs_accounts_fixture()
      plan = plan_fixture()
      sub = subscription_fixture(%{plan: plan})
      customer_id = sub.customer_id

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      :ok = VolumeStudio.on_customer_soft_delete(customer_id, now)

      deleted_sub = Ledgr.Repo.get!(Ledgr.Domains.VolumeStudio.Subscriptions.Subscription, sub.id)
      assert deleted_sub.deleted_at != nil
    end

    test "returns :ok" do
      assert :ok = VolumeStudio.on_customer_soft_delete(0, DateTime.utc_now())
    end
  end
end
