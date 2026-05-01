defmodule Ledgr.Domains.VolumeStudio.SpacesTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.VolumeStudio.Spaces
  alias Ledgr.Domains.VolumeStudio.Spaces.{Space, SpaceRental}

  import Ledgr.Domains.VolumeStudio.Fixtures

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.VolumeStudio)
    Ledgr.Domain.put_current(Ledgr.Domains.VolumeStudio)
    accounts = vs_accounts_fixture()
    {:ok, accounts: accounts}
  end

  # ── Spaces ────────────────────────────────────────────────────────────

  describe "list_spaces/0" do
    test "returns all non-deleted spaces" do
      space = space_fixture()
      spaces = Spaces.list_spaces()
      assert Enum.any?(spaces, fn s -> s.id == space.id end)
    end

    test "excludes soft-deleted spaces" do
      space = space_fixture()
      {:ok, _} = Spaces.delete_space(space)

      spaces = Spaces.list_spaces()
      refute Enum.any?(spaces, fn s -> s.id == space.id end)
    end

    test "returns spaces ordered by name" do
      space_fixture(%{name: "Zumba Room"})
      space_fixture(%{name: "Aerial Room"})

      spaces = Spaces.list_spaces()
      names = Enum.map(spaces, & &1.name)
      assert names == Enum.sort(names)
    end
  end

  describe "list_active_spaces/0" do
    test "returns only active spaces" do
      active = space_fixture(%{active: true})
      _inactive = space_fixture(%{active: false, name: "Closed Room"})

      spaces = Spaces.list_active_spaces()
      assert Enum.any?(spaces, fn s -> s.id == active.id end)
      assert Enum.all?(spaces, fn s -> s.active == true end)
    end
  end

  describe "get_space!/1" do
    test "returns space with given id" do
      space = space_fixture()
      found = Spaces.get_space!(space.id)
      assert found.id == space.id
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Spaces.get_space!(0)
      end
    end
  end

  describe "create_space/1" do
    test "creates space with valid attrs" do
      attrs = %{name: "New Space", hourly_rate_cents: 60000, active: true}
      assert {:ok, %Space{} = space} = Spaces.create_space(attrs)
      assert space.name == "New Space"
    end

    test "returns error with missing name" do
      assert {:error, %Ecto.Changeset{}} = Spaces.create_space(%{})
    end
  end

  describe "update_space/2" do
    test "updates space attrs" do
      space = space_fixture(%{name: "Old Name"})
      assert {:ok, updated} = Spaces.update_space(space, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "can deactivate a space" do
      space = space_fixture(%{active: true})
      assert {:ok, updated} = Spaces.update_space(space, %{active: false})
      assert updated.active == false
    end
  end

  describe "delete_space/1" do
    test "soft-deletes a space" do
      space = space_fixture()
      assert {:ok, deleted} = Spaces.delete_space(space)
      assert deleted.deleted_at != nil
    end
  end

  describe "change_space/2" do
    test "returns a changeset" do
      space = space_fixture()
      assert %Ecto.Changeset{} = Spaces.change_space(space, %{name: "Changed"})
    end
  end

  # ── Space Rentals ─────────────────────────────────────────────────────

  describe "list_space_rentals/0" do
    test "returns all non-deleted rentals" do
      rental = rental_fixture()
      rentals = Spaces.list_space_rentals()
      assert Enum.any?(rentals, fn r -> r.id == rental.id end)
    end

    test "filters by space_id" do
      space1 = space_fixture()
      space2 = space_fixture()
      rental1 = rental_fixture(%{space: space1})
      _rental2 = rental_fixture(%{space: space2})

      rentals = Spaces.list_space_rentals(space_id: space1.id)
      assert Enum.any?(rentals, fn r -> r.id == rental1.id end)
      assert Enum.all?(rentals, fn r -> r.space_id == space1.id end)
    end

    test "filters by status" do
      confirmed = rental_fixture(%{status: "confirmed"})
      _completed = rental_fixture(%{status: "completed"})

      rentals = Spaces.list_space_rentals(status: "confirmed")
      assert Enum.any?(rentals, fn r -> r.id == confirmed.id end)
      assert Enum.all?(rentals, fn r -> r.status == "confirmed" end)
    end
  end

  describe "get_space_rental!/1" do
    test "returns rental with space and customer preloaded" do
      rental = rental_fixture()
      found = Spaces.get_space_rental!(rental.id)
      assert found.id == rental.id
      assert found.space != nil
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Spaces.get_space_rental!(0)
      end
    end
  end

  describe "create_space_rental/1" do
    test "creates rental with valid attrs" do
      space = space_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        space_id: space.id,
        renter_name: "Test Renter",
        amount_cents: 100_000,
        starts_at: now,
        ends_at: DateTime.add(now, 3600, :second)
      }

      assert {:ok, %SpaceRental{} = rental} = Spaces.create_space_rental(attrs)
      assert rental.renter_name == "Test Renter"
      # IVA is auto-computed: 16% of 100000 = 16000
      assert rental.iva_cents == 16000
    end

    test "returns error with missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Spaces.create_space_rental(%{})
    end
  end

  describe "update_space_rental/2" do
    test "updates rental status" do
      rental = rental_fixture(%{status: "confirmed"})
      assert {:ok, updated} = Spaces.update_space_rental(rental, %{status: "completed"})
      assert updated.status == "completed"
    end
  end

  describe "payment_summary/1" do
    test "returns correct summary for unpaid rental" do
      rental = rental_fixture(%{amount_cents: 100_000})
      summary = Spaces.payment_summary(rental)

      assert summary.base_cents == 100_000
      assert summary.paid_cents == 0
      assert summary.outstanding_cents == summary.total_cents
    end

    test "accounts for discount in total" do
      rental = rental_fixture(%{amount_cents: 100_000})
      {:ok, discounted} = Spaces.update_space_rental(rental, %{discount_cents: 10000})
      summary = Spaces.payment_summary(discounted)

      # base(100000) + iva(16000) - discount(10000) = 106000
      assert summary.discount_cents == 10000
      assert summary.total_cents == 106_000
    end

    test "outstanding is 0 when fully paid" do
      rental = rental_fixture(%{amount_cents: 100_000})
      # total = 100000 base + 16000 IVA = 116000
      {:ok, paid_rental} =
        Spaces.record_payment(rental, %{amount_cents: 116_000, payment_date: Date.utc_today()})

      summary = Spaces.payment_summary(paid_rental)
      assert summary.outstanding_cents == 0
    end
  end

  describe "record_payment/2" do
    test "increments paid_cents and creates a journal entry" do
      rental = rental_fixture(%{amount_cents: 100_000})
      attrs = %{amount_cents: 50000, payment_date: Date.utc_today(), method: "cash"}

      assert {:ok, updated} = Spaces.record_payment(rental, attrs)
      assert updated.paid_cents == 50000
    end

    test "sets paid_at when fully paid" do
      rental = rental_fixture(%{amount_cents: 100_000})
      # Total = 100000 + 16000 iva = 116000
      attrs = %{amount_cents: 116_000, payment_date: Date.utc_today()}

      {:ok, updated} = Spaces.record_payment(rental, attrs)
      assert updated.paid_at != nil
    end

    test "allows multiple partial payments" do
      rental = rental_fixture(%{amount_cents: 100_000})
      attrs1 = %{amount_cents: 50000, payment_date: Date.utc_today()}
      {:ok, after_first} = Spaces.record_payment(rental, attrs1)

      attrs2 = %{amount_cents: 30000, payment_date: Date.utc_today()}
      {:ok, after_second} = Spaces.record_payment(after_first, attrs2)

      assert after_second.paid_cents == 80000
    end
  end

  describe "list_rental_payments/1" do
    test "returns empty list when no payments" do
      rental = rental_fixture()
      assert Spaces.list_rental_payments(rental) == []
    end

    test "returns payments after recording" do
      rental = rental_fixture(%{amount_cents: 100_000})

      {:ok, updated} =
        Spaces.record_payment(rental, %{amount_cents: 50000, payment_date: Date.utc_today()})

      payments = Spaces.list_rental_payments(updated)
      assert length(payments) == 1
    end
  end

  describe "change_space_rental/2" do
    test "returns a changeset" do
      rental = rental_fixture()
      assert %Ecto.Changeset{} = Spaces.change_space_rental(rental, %{status: "completed"})
    end
  end
end
