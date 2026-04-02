defmodule Ledgr.Domains.VolumeStudio.SubscriptionsTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.VolumeStudio.Subscriptions
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
  alias Ledgr.Repo

  import Ledgr.Domains.VolumeStudio.Fixtures

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.VolumeStudio)
    Ledgr.Domain.put_current(Ledgr.Domains.VolumeStudio)
    accounts = vs_accounts_fixture()
    {:ok, accounts: accounts}
  end

  describe "list_subscriptions/0" do
    test "returns all non-deleted subscriptions" do
      sub = subscription_fixture()
      subs = Subscriptions.list_subscriptions()
      assert Enum.any?(subs, fn s -> s.id == sub.id end)
    end

    test "filters by status" do
      active = subscription_fixture(%{status: "active"})
      _cancelled = subscription_fixture(%{status: "cancelled"})

      subs = Subscriptions.list_subscriptions(status: "active")
      assert Enum.any?(subs, fn s -> s.id == active.id end)
      assert Enum.all?(subs, fn s -> s.status == "active" end)
    end

    test "filters by customer_id" do
      sub = subscription_fixture()
      other_sub = subscription_fixture()

      subs = Subscriptions.list_subscriptions(customer_id: sub.customer_id)
      assert Enum.any?(subs, fn s -> s.id == sub.id end)
      refute Enum.any?(subs, fn s -> s.id == other_sub.id end)
    end

    test "filters by plan_type" do
      package_plan = package_plan_fixture()
      _extra_sub = subscription_fixture(%{plan: extra_plan_fixture()})
      package_sub = subscription_fixture(%{plan: package_plan})

      subs = Subscriptions.list_subscriptions(plan_type: "package")
      assert Enum.any?(subs, fn s -> s.id == package_sub.id end)
    end
  end

  describe "get_subscription!/1" do
    test "returns subscription with plan and customer preloaded" do
      sub = subscription_fixture()
      found = Subscriptions.get_subscription!(sub.id)
      assert found.id == sub.id
      assert found.subscription_plan != nil
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Subscriptions.get_subscription!(0)
      end
    end
  end

  describe "create_subscription/1" do
    test "creates subscription with valid attrs" do
      plan = plan_fixture()
      customer_id = create_customer()
      today = Date.utc_today()

      attrs = %{
        "customer_id" => customer_id,
        "subscription_plan_id" => plan.id,
        "starts_on" => today,
        "ends_on" => Date.add(today, 30),
        "status" => "active"
      }

      assert {:ok, %Subscription{} = sub} = Subscriptions.create_subscription(attrs)
      assert sub.customer_id == customer_id
    end

    test "computes iva_cents from plan price" do
      plan = plan_fixture(%{price_cents: 50000})
      customer_id = create_customer()
      today = Date.utc_today()

      attrs = %{
        "customer_id" => customer_id,
        "subscription_plan_id" => plan.id,
        "starts_on" => today,
        "ends_on" => Date.add(today, 30)
      }

      {:ok, sub} = Subscriptions.create_subscription(attrs)
      # IVA = 16% of 50000 = 8000
      assert sub.iva_cents == 8000
    end

    test "applies discount when computing iva_cents" do
      plan = plan_fixture(%{price_cents: 50000})
      customer_id = create_customer()
      today = Date.utc_today()

      attrs = %{
        "customer_id" => customer_id,
        "subscription_plan_id" => plan.id,
        "starts_on" => today,
        "ends_on" => Date.add(today, 30),
        "discount_cents" => 10000
      }

      {:ok, sub} = Subscriptions.create_subscription(attrs)
      # IVA = 16% of (50000 - 10000) = 16% of 40000 = 6400
      assert sub.iva_cents == 6400
    end

    test "returns error with missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Subscriptions.create_subscription(%{})
    end
  end

  describe "update_subscription/2" do
    test "updates subscription notes" do
      sub = subscription_fixture()
      assert {:ok, updated} = Subscriptions.update_subscription(sub, %{"notes" => "VIP member"})
      assert updated.notes == "VIP member"
    end

    test "recomputes iva when plan changes" do
      original_plan = plan_fixture(%{price_cents: 50000})
      new_plan = plan_fixture(%{price_cents: 100000})
      customer_id = create_customer()
      today = Date.utc_today()

      {:ok, sub} = Subscriptions.create_subscription(%{
        "customer_id" => customer_id,
        "subscription_plan_id" => original_plan.id,
        "starts_on" => today,
        "ends_on" => Date.add(today, 30)
      })

      {:ok, updated} = Subscriptions.update_subscription(sub, %{"subscription_plan_id" => new_plan.id})
      # IVA should update to 16% of 100000 = 16000
      assert updated.iva_cents == 16000
    end
  end

  describe "record_payment/3" do
    test "increases deferred_revenue_cents and paid_cents" do
      sub = subscription_fixture(%{deferred_revenue_cents: 0, paid_cents: 0})
      {:ok, updated} = Subscriptions.record_payment(sub, 50000)

      assert updated.paid_cents == 50000
      assert updated.deferred_revenue_cents > 0
    end

    test "creates a journal entry for the payment" do
      sub = subscription_fixture()
      {:ok, _} = Subscriptions.record_payment(sub, 30000)

      entries = Subscriptions.list_payments_for_subscription(sub)
      assert length(entries) == 1
    end

    test "allows multiple payments on same subscription" do
      sub = subscription_fixture(%{deferred_revenue_cents: 0, paid_cents: 0})
      {:ok, _} = Subscriptions.record_payment(sub, 10000)

      # Reload after first payment
      sub2 = Repo.get!(Subscription, sub.id) |> Repo.preload(:subscription_plan)
      {:ok, _} = Subscriptions.record_payment(sub2, 10000)

      entries = Subscriptions.list_payments_for_subscription(sub)
      assert length(entries) == 2
    end

    test "auto-preloads plan if not loaded" do
      sub = Repo.get!(Subscription, subscription_fixture().id)
      refute Ecto.assoc_loaded?(sub.subscription_plan)

      assert {:ok, _} = Subscriptions.record_payment(sub, 20000)
    end
  end

  describe "recognize_revenue/2" do
    test "moves amount from deferred to recognized" do
      sub = subscription_fixture(%{deferred_revenue_cents: 10000})
      {:ok, updated} = Subscriptions.recognize_revenue(sub, 5000)

      assert updated.deferred_revenue_cents == 5000
      assert updated.recognized_revenue_cents == 5000
    end

    test "caps at available deferred revenue" do
      sub = subscription_fixture(%{deferred_revenue_cents: 3000})
      {:ok, updated} = Subscriptions.recognize_revenue(sub, 10000)

      assert updated.deferred_revenue_cents == 0
      assert updated.recognized_revenue_cents == 3000
    end

    test "returns error when no deferred revenue" do
      sub = subscription_fixture(%{deferred_revenue_cents: 0})
      assert {:error, :no_deferred_revenue} = Subscriptions.recognize_revenue(sub, 1000)
    end
  end

  describe "apply_refund/2" do
    test "deducts from deferred_revenue_cents first" do
      sub = subscription_fixture(%{deferred_revenue_cents: 20000, recognized_revenue_cents: 10000, paid_cents: 30000})
      {:ok, updated} = Subscriptions.apply_refund(sub, 15000)

      assert updated.deferred_revenue_cents == 5000
      assert updated.recognized_revenue_cents == 10000
      assert updated.paid_cents == 15000
    end

    test "deducts from recognized_revenue_cents when deferred is exhausted" do
      sub = subscription_fixture(%{deferred_revenue_cents: 5000, recognized_revenue_cents: 10000, paid_cents: 15000})
      {:ok, updated} = Subscriptions.apply_refund(sub, 10000)

      assert updated.deferred_revenue_cents == 0
      assert updated.recognized_revenue_cents == 5000
    end
  end

  describe "cancel/1" do
    test "sets status to cancelled and ends_on to today" do
      sub = subscription_fixture(%{status: "active"})
      {:ok, cancelled} = Subscriptions.cancel(sub)

      assert cancelled.status == "cancelled"
      assert cancelled.ends_on == LedgrWeb.Helpers.DomainHelpers.today_mx()
    end

    test "recognizes remaining deferred revenue on cancellation" do
      sub = subscription_fixture(%{deferred_revenue_cents: 20000, status: "active"})
      {:ok, cancelled} = Subscriptions.cancel(sub)
      reloaded = Repo.get!(Subscription, cancelled.id)

      assert reloaded.deferred_revenue_cents == 0
      assert reloaded.recognized_revenue_cents == 20000
    end
  end

  describe "finalize/2" do
    test "sets status to completed and recognizes deferred revenue" do
      sub = subscription_fixture(%{deferred_revenue_cents: 15000, status: "active"})
      {:ok, finalized} = Subscriptions.finalize(sub, "completed")
      reloaded = Repo.get!(Subscription, finalized.id)

      assert reloaded.status == "completed"
      assert reloaded.deferred_revenue_cents == 0
    end

    test "sets status to expired" do
      sub = subscription_fixture(%{status: "active"})
      {:ok, finalized} = Subscriptions.finalize(sub, "expired")
      assert finalized.status == "expired"
    end
  end

  describe "redeem_extra/1" do
    test "increments classes_used" do
      plan = extra_plan_fixture()
      sub = subscription_fixture(%{plan: plan, deferred_revenue_cents: 0})
      {:ok, updated} = Subscriptions.redeem_extra(sub)

      assert updated.classes_used == 1
    end

    test "recognizes deferred revenue for extra plans" do
      plan = extra_plan_fixture()
      sub = subscription_fixture(%{plan: plan, deferred_revenue_cents: 10000})
      {:ok, updated} = Subscriptions.redeem_extra(sub)

      assert updated.classes_used == 1
      # revenue recognized via accounting
    end
  end

  describe "payment_summary/1" do
    test "returns correct summary with no payments" do
      plan = plan_fixture(%{price_cents: 50000})
      sub = subscription_fixture(%{plan: plan, discount_cents: 0})

      summary = Subscriptions.payment_summary(sub)

      assert summary.base_cents == 50000
      assert summary.total_paid == 0
      assert summary.outstanding_cents > 0
    end

    test "accounts for discount in effective price" do
      plan = plan_fixture(%{price_cents: 50000})
      sub = subscription_fixture(%{plan: plan, discount_cents: 10000})

      summary = Subscriptions.payment_summary(sub)

      assert summary.discount_cents == 10000
      assert summary.effective_price == 40000
    end

    test "auto-preloads plan if not loaded" do
      sub = Repo.get!(Subscription, subscription_fixture().id)
      refute Ecto.assoc_loaded?(sub.subscription_plan)
      summary = Subscriptions.payment_summary(sub)
      assert is_map(summary)
    end
  end

  describe "get_soonest_expiring_subscription/1" do
    test "returns nil when no active subscriptions" do
      customer_id = create_customer()
      assert is_nil(Subscriptions.get_soonest_expiring_subscription(customer_id))
    end

    test "returns the soonest expiring active subscription" do
      customer_id = create_customer()
      today = Date.utc_today()

      plan = plan_fixture()
      sub_sooner = subscription_fixture(%{
        customer_id: customer_id,
        plan: plan,
        starts_on: today,
        ends_on: Date.add(today, 5)
      })
      _sub_later = subscription_fixture(%{
        customer_id: customer_id,
        plan: plan,
        starts_on: today,
        ends_on: Date.add(today, 30)
      })

      result = Subscriptions.get_soonest_expiring_subscription(customer_id)
      assert result.id == sub_sooner.id
    end

    test "excludes subscriptions that have expired" do
      customer_id = create_customer()
      today = LedgrWeb.Helpers.DomainHelpers.today_mx()
      plan = plan_fixture()

      _expired_sub = subscription_fixture(%{
        customer_id: customer_id,
        plan: plan,
        starts_on: Date.add(today, -30),
        ends_on: Date.add(today, -1)
      })

      result = Subscriptions.get_soonest_expiring_subscription(customer_id)
      assert is_nil(result)
    end
  end

  describe "delete_payment/2" do
    test "reverses a subscription payment and updates deferred revenue" do
      sub = subscription_fixture(%{deferred_revenue_cents: 0, paid_cents: 0})
      {:ok, updated_sub} = Subscriptions.record_payment(sub, 30000)

      entries = Subscriptions.list_payments_for_subscription(sub)
      entry = hd(entries)

      reloaded_sub = Repo.get!(Subscription, updated_sub.id) |> Repo.preload(:subscription_plan)

      {:ok, _} = Subscriptions.delete_payment(reloaded_sub, entry)

      final_sub = Repo.get!(Subscription, sub.id)
      assert final_sub.paid_cents == 0
    end
  end

  describe "list_bookings_for_subscription/1" do
    test "returns empty list when no bookings" do
      sub = subscription_fixture()
      bookings = Subscriptions.list_bookings_for_subscription(sub)
      assert bookings == []
    end
  end

  describe "change_subscription/2" do
    test "returns a changeset" do
      sub = subscription_fixture()
      assert %Ecto.Changeset{} = Subscriptions.change_subscription(sub, %{notes: "test"})
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp create_customer do
    unique = System.unique_integer([:positive])
    {:ok, customer} = Ledgr.Core.Customers.create_customer(%{
      name: "Customer #{unique}",
      phone: "555#{unique}"
    })
    customer.id
  end
end
