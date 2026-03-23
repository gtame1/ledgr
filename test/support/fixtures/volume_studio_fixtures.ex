defmodule Ledgr.Domains.VolumeStudio.Fixtures do
  @moduledoc """
  Test helpers for creating Volume Studio entities and their required accounts.
  """

  alias Ledgr.Core.Accounting
  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.{
    SubscriptionPlans,
    Subscriptions,
    Instructors,
    ClassSessions,
    Consultations,
    Spaces
  }
  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans.SubscriptionPlan
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
  alias Ledgr.Domains.VolumeStudio.Instructors.Instructor
  alias Ledgr.Domains.VolumeStudio.ClassSessions.{ClassSession, ClassBooking}
  alias Ledgr.Domains.VolumeStudio.Consultations.Consultation
  alias Ledgr.Domains.VolumeStudio.Spaces.{Space, SpaceRental}

  @doc """
  Creates all accounting accounts needed for Volume Studio operations.
  Returns a map keyed by account code.
  """
  def vs_accounts_fixture do
    accounts = [
      %{code: "1000", name: "Cash",                         type: "asset",     normal_balance: "debit",  is_cash: true},
      %{code: "1010", name: "Bank Transfer",                type: "asset",     normal_balance: "debit",  is_cash: true},
      %{code: "1020", name: "Card Terminal",                type: "asset",     normal_balance: "debit",  is_cash: true},
      %{code: "1100", name: "Accounts Receivable",          type: "asset",     normal_balance: "debit",  is_cash: false},
      %{code: "2100", name: "IVA Payable",                  type: "liability", normal_balance: "credit", is_cash: false},
      %{code: "2200", name: "Deferred Subscription Revenue",type: "liability", normal_balance: "credit", is_cash: false},
      %{code: "2300", name: "Owed Change Payable",          type: "liability", normal_balance: "credit", is_cash: false},
      %{code: "3000", name: "Owner's Equity",               type: "equity",    normal_balance: "credit", is_cash: false},
      %{code: "3050", name: "Retained Earnings",            type: "equity",    normal_balance: "credit", is_cash: false},
      %{code: "3100", name: "Owner's Drawings",             type: "equity",    normal_balance: "debit",  is_cash: false},
      %{code: "4000", name: "Subscription Revenue",         type: "revenue",   normal_balance: "credit", is_cash: false},
      %{code: "4020", name: "Consultation Revenue",         type: "revenue",   normal_balance: "credit", is_cash: false},
      %{code: "4030", name: "Space Rental Revenue",         type: "revenue",   normal_balance: "credit", is_cash: false},
      %{code: "4040", name: "Partner Fee Revenue",          type: "revenue",   normal_balance: "credit", is_cash: false}
    ]

    Enum.map(accounts, fn attrs ->
      account =
        case Accounting.get_account_by_code(attrs.code) do
          nil ->
            {:ok, a} = Accounting.create_account(attrs)
            a
          existing ->
            existing
        end

      {account.code, account}
    end)
    |> Map.new()
  end

  @doc "Creates a subscription plan with given attrs."
  def plan_fixture(attrs \\ %{}) do
    {:ok, plan} =
      %SubscriptionPlan{}
      |> SubscriptionPlan.changeset(
        Enum.into(attrs, %{
          name: "Test Plan #{System.unique_integer([:positive])}",
          price_cents: 50000,
          plan_type: "membership",
          duration_months: 1
        })
      )
      |> Repo.insert()

    plan
  end

  @doc "Creates a package plan (class_limit set, plan_type = package)."
  def package_plan_fixture(attrs \\ %{}) do
    plan_fixture(
      Enum.into(attrs, %{
        name: "Package Plan #{System.unique_integer([:positive])}",
        price_cents: 30000,
        plan_type: "package",
        class_limit: 10,
        duration_days: 30
      })
    )
  end

  @doc "Creates an extra plan (single-use, plan_type = extra)."
  def extra_plan_fixture(attrs \\ %{}) do
    plan_fixture(
      Enum.into(attrs, %{
        name: "Extra #{System.unique_integer([:positive])}",
        price_cents: 10000,
        plan_type: "extra",
        duration_days: 1
      })
    )
  end

  @doc "Creates an instructor."
  def instructor_fixture(attrs \\ %{}) do
    {:ok, instructor} =
      %Instructor{}
      |> Instructor.changeset(
        Enum.into(attrs, %{
          name: "Instructor #{System.unique_integer([:positive])}",
          active: true
        })
      )
      |> Repo.insert()

    instructor
  end

  @doc "Creates a class session."
  def session_fixture(attrs \\ %{}) do
    instructor = attrs[:instructor] || instructor_fixture()

    {:ok, session} =
      %ClassSession{}
      |> ClassSession.changeset(
        attrs
        |> Map.drop([:instructor])
        |> Enum.into(%{
          name: "Yoga Class #{System.unique_integer([:positive])}",
          instructor_id: instructor.id,
          scheduled_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
          capacity: 20,
          status: "scheduled"
        })
      )
      |> Repo.insert()

    session
  end

  @doc "Creates a class booking."
  def booking_fixture(attrs \\ %{}) do
    customer_id = attrs[:customer_id] || begin_customer()
    session = attrs[:session] || session_fixture()

    {:ok, booking} =
      %ClassBooking{}
      |> ClassBooking.changeset(
        attrs
        |> Map.drop([:session])
        |> Enum.into(%{
          customer_id: customer_id,
          class_session_id: session.id,
          status: "booked"
        })
      )
      |> Repo.insert()

    booking
  end

  @doc "Creates a subscription (no IVA by default)."
  def subscription_fixture(attrs \\ %{}) do
    customer_id = attrs[:customer_id] || begin_customer()
    plan = attrs[:plan] || plan_fixture()
    today = Date.utc_today()

    {:ok, sub} =
      %Subscription{}
      |> Subscription.changeset(
        attrs
        |> Map.drop([:plan])
        |> Enum.into(%{
          customer_id: customer_id,
          subscription_plan_id: plan.id,
          starts_on: today,
          ends_on: Date.add(today, 30),
          status: "active"
        })
      )
      |> Repo.insert()

    sub |> Repo.preload(:subscription_plan)
  end

  @doc "Creates a consultation."
  def consultation_fixture(attrs \\ %{}) do
    customer_id = attrs[:customer_id] || begin_customer()
    instructor = attrs[:instructor] || instructor_fixture()

    {:ok, consultation} =
      %Consultation{}
      |> Consultation.changeset(
        attrs
        |> Map.drop([:instructor])
        |> Enum.into(%{
          customer_id: customer_id,
          instructor_id: instructor.id,
          scheduled_at: DateTime.utc_now() |> DateTime.add(86400, :second) |> DateTime.truncate(:second),
          amount_cents: 80000,
          status: "scheduled"
        })
      )
      |> Repo.insert()

    consultation
  end

  @doc "Creates a space."
  def space_fixture(attrs \\ %{}) do
    {:ok, space} =
      %Space{}
      |> Space.changeset(
        Enum.into(attrs, %{
          name: "Studio #{System.unique_integer([:positive])}",
          active: true,
          hourly_rate_cents: 50000
        })
      )
      |> Repo.insert()

    space
  end

  @doc "Creates a space rental."
  def rental_fixture(attrs \\ %{}) do
    space = attrs[:space] || space_fixture()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, rental} =
      %SpaceRental{}
      |> SpaceRental.changeset(
        attrs
        |> Map.drop([:space])
        |> Enum.into(%{
          space_id: space.id,
          renter_name: "Test Renter",
          amount_cents: 100000,
          starts_at: now,
          ends_at: DateTime.add(now, 3600, :second),
          status: "confirmed"
        })
      )
      |> Repo.insert()

    rental
  end

  # Creates a minimal customer and returns their ID
  defp begin_customer do
    unique = System.unique_integer([:positive])
    {:ok, customer} =
      Ledgr.Core.Customers.create_customer(%{
        name: "VS Customer #{unique}",
        phone: "555#{unique}",
        email: "vs#{unique}@test.com"
      })

    customer.id
  end
end
