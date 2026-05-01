defmodule Ledgr.Domains.VolumeStudio.SubscriptionPlansTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans
  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans.SubscriptionPlan

  import Ledgr.Domains.VolumeStudio.Fixtures

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.VolumeStudio)
    :ok
  end

  describe "list_subscription_plans/0" do
    test "returns all non-deleted plans" do
      plan1 = plan_fixture(%{name: "Monthly", price_cents: 50000})

      plan2 =
        plan_fixture(%{
          name: "Package",
          price_cents: 30000,
          plan_type: "package",
          class_limit: 10,
          duration_days: 30
        })

      plans = SubscriptionPlans.list_subscription_plans()
      ids = Enum.map(plans, & &1.id)

      assert plan1.id in ids
      assert plan2.id in ids
    end

    test "filters by plan_type" do
      _membership = plan_fixture(%{plan_type: "membership"})
      package = package_plan_fixture()

      packages = SubscriptionPlans.list_subscription_plans(plan_type: "package")
      assert Enum.all?(packages, fn p -> p.plan_type == "package" end)
      assert Enum.any?(packages, fn p -> p.id == package.id end)
    end

    test "excludes soft-deleted plans" do
      plan = plan_fixture()
      {:ok, _} = SubscriptionPlans.delete_subscription_plan(plan)

      plans = SubscriptionPlans.list_subscription_plans()
      refute Enum.any?(plans, fn p -> p.id == plan.id end)
    end
  end

  describe "list_active_subscription_plans/0" do
    test "returns only active plans" do
      active = plan_fixture(%{active: true})
      _inactive = plan_fixture(%{active: false, name: "Inactive Plan"})

      plans = SubscriptionPlans.list_active_subscription_plans()
      assert Enum.any?(plans, fn p -> p.id == active.id end)
      assert Enum.all?(plans, fn p -> p.active == true end)
    end
  end

  describe "list_active_extra_plans/0" do
    test "returns only active extra-type plans" do
      extra = extra_plan_fixture(%{active: true})
      _membership = plan_fixture(%{active: true})

      plans = SubscriptionPlans.list_active_extra_plans()
      assert Enum.any?(plans, fn p -> p.id == extra.id end)
      assert Enum.all?(plans, fn p -> p.plan_type == "extra" end)
    end
  end

  describe "get_subscription_plan!/1" do
    test "returns the plan with given id" do
      plan = plan_fixture()
      found = SubscriptionPlans.get_subscription_plan!(plan.id)
      assert found.id == plan.id
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn ->
        SubscriptionPlans.get_subscription_plan!(0)
      end
    end
  end

  describe "get_plan_by_name/1" do
    test "returns plan matching name" do
      plan = plan_fixture(%{name: "Unique Plan Name 999"})
      found = SubscriptionPlans.get_plan_by_name("Unique Plan Name 999")
      assert found.id == plan.id
    end

    test "returns nil when name not found" do
      assert is_nil(SubscriptionPlans.get_plan_by_name("nonexistent plan xyz"))
    end
  end

  describe "create_subscription_plan/1" do
    test "creates plan with valid attrs" do
      attrs = %{name: "New Plan", price_cents: 40000, plan_type: "membership", duration_months: 1}
      assert {:ok, %SubscriptionPlan{} = plan} = SubscriptionPlans.create_subscription_plan(attrs)
      assert plan.name == "New Plan"
      assert plan.price_cents == 40000
    end

    test "returns error changeset with invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = SubscriptionPlans.create_subscription_plan(%{})
    end

    test "requires price_cents > 0" do
      assert {:error, changeset} =
               SubscriptionPlans.create_subscription_plan(%{name: "Bad", price_cents: 0})

      assert errors_on(changeset)[:price_cents]
    end
  end

  describe "update_subscription_plan/2" do
    test "updates a plan's name and price" do
      plan = plan_fixture(%{name: "Old Name"})

      assert {:ok, updated} =
               SubscriptionPlans.update_subscription_plan(plan, %{
                 name: "New Name",
                 price_cents: 60000
               })

      assert updated.name == "New Name"
      assert updated.price_cents == 60000
    end

    test "returns error on invalid attrs" do
      plan = plan_fixture()

      assert {:error, %Ecto.Changeset{}} =
               SubscriptionPlans.update_subscription_plan(plan, %{price_cents: 0})
    end
  end

  describe "delete_subscription_plan/1" do
    test "soft-deletes a plan" do
      plan = plan_fixture()
      assert {:ok, deleted} = SubscriptionPlans.delete_subscription_plan(plan)
      assert deleted.deleted_at != nil
    end

    test "deleted plan no longer appears in list" do
      plan = plan_fixture()
      {:ok, _} = SubscriptionPlans.delete_subscription_plan(plan)

      plans = SubscriptionPlans.list_subscription_plans()
      refute Enum.any?(plans, fn p -> p.id == plan.id end)
    end
  end

  describe "change_subscription_plan/2" do
    test "returns a changeset" do
      plan = plan_fixture()
      changeset = SubscriptionPlans.change_subscription_plan(plan, %{name: "Changed"})
      assert %Ecto.Changeset{} = changeset
    end
  end
end
