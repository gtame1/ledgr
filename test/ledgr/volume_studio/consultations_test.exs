defmodule Ledgr.Domains.VolumeStudio.ConsultationsTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.VolumeStudio.Consultations
  alias Ledgr.Domains.VolumeStudio.Consultations.Consultation

  import Ledgr.Domains.VolumeStudio.Fixtures

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.VolumeStudio)
    Ledgr.Domain.put_current(Ledgr.Domains.VolumeStudio)
    accounts = vs_accounts_fixture()
    {:ok, accounts: accounts}
  end

  describe "list_consultations/0" do
    test "returns all non-deleted consultations" do
      consultation = consultation_fixture()
      consultations = Consultations.list_consultations()
      assert Enum.any?(consultations, fn c -> c.id == consultation.id end)
    end

    test "filters by status" do
      scheduled = consultation_fixture(%{status: "scheduled"})
      _completed = consultation_fixture(%{status: "completed"})

      consultations = Consultations.list_consultations(status: "scheduled")
      assert Enum.any?(consultations, fn c -> c.id == scheduled.id end)
      assert Enum.all?(consultations, fn c -> c.status == "scheduled" end)
    end

    test "filters by from/to datetime" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      near = DateTime.add(now, 7200, :second)
      far = DateTime.add(now, 86400 * 7, :second)

      near_consultation = consultation_fixture(%{scheduled_at: near})
      _far_consultation = consultation_fixture(%{scheduled_at: far})

      consultations = Consultations.list_consultations(
        from: DateTime.add(now, 3600, :second),
        to: DateTime.add(now, 14400, :second)
      )

      assert Enum.any?(consultations, fn c -> c.id == near_consultation.id end)
    end
  end

  describe "get_consultation!/1" do
    test "returns consultation with customer preloaded" do
      consultation = consultation_fixture()
      found = Consultations.get_consultation!(consultation.id)
      assert found.id == consultation.id
      assert found.customer != nil
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Consultations.get_consultation!(0)
      end
    end
  end

  describe "create_consultation/1" do
    test "creates with valid attrs" do
      customer_id = create_customer()
      scheduled_at = DateTime.utc_now() |> DateTime.add(86400) |> DateTime.truncate(:second)

      attrs = %{
        customer_id: customer_id,
        instructor_name: "Dr. Test",
        scheduled_at: scheduled_at,
        amount_cents: 80000
      }

      assert {:ok, %Consultation{} = c} = Consultations.create_consultation(attrs)
      assert c.amount_cents == 80000
      assert c.instructor_name == "Dr. Test"
    end

    test "returns error with missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Consultations.create_consultation(%{})
    end

    test "returns error with invalid amount" do
      customer_id = create_customer()

      attrs = %{
        customer_id: customer_id,
        scheduled_at: DateTime.utc_now() |> DateTime.truncate(:second),
        amount_cents: 0
      }

      assert {:error, changeset} = Consultations.create_consultation(attrs)
      assert errors_on(changeset)[:amount_cents]
    end
  end

  describe "update_consultation/2" do
    test "updates status" do
      consultation = consultation_fixture(%{status: "scheduled"})
      assert {:ok, updated} = Consultations.update_consultation(consultation, %{status: "completed"})
      assert updated.status == "completed"
    end

    test "updates amount" do
      consultation = consultation_fixture()
      assert {:ok, updated} = Consultations.update_consultation(consultation, %{amount_cents: 100000})
      assert updated.amount_cents == 100000
    end
  end

  describe "payment_summary/1" do
    test "returns correct summary for unpaid consultation" do
      consultation = consultation_fixture(%{amount_cents: 80000})
      summary = Consultations.payment_summary(consultation)

      assert summary.amount_cents == 80000
      assert summary.paid == false
      assert summary.outstanding_cents == summary.total_cents
    end

    test "returns zero outstanding when paid" do
      consultation = consultation_fixture(%{amount_cents: 80000})
      {:ok, paid} = Consultations.update_consultation(consultation, %{paid_at: Date.utc_today()})
      summary = Consultations.payment_summary(paid)

      assert summary.paid == true
      assert summary.outstanding_cents == 0
    end

    test "includes iva_cents in total" do
      consultation = consultation_fixture(%{amount_cents: 80000, iva_cents: 12800})
      summary = Consultations.payment_summary(consultation)

      assert summary.total_cents == 92800
    end
  end

  describe "record_payment/3" do
    test "marks consultation as paid" do
      consultation = consultation_fixture(%{amount_cents: 80000})
      assert {:ok, updated} = Consultations.record_payment(consultation, 80000)
      assert updated.paid_at != nil
    end

    test "creates a journal entry for the payment" do
      consultation = consultation_fixture(%{amount_cents: 80000})
      {:ok, _} = Consultations.record_payment(consultation, 80000)

      entries = Consultations.list_payments_for_consultation(consultation)
      assert length(entries) == 1
    end

    test "returns error if already paid" do
      consultation = consultation_fixture()
      {:ok, paid} = Consultations.update_consultation(consultation, %{paid_at: Date.utc_today()})
      assert {:error, :already_paid} = Consultations.record_payment(paid, 80000)
    end

    test "uses custom paid_to_account_code when provided" do
      consultation = consultation_fixture(%{amount_cents: 50000})
      assert {:ok, _} = Consultations.record_payment(consultation, 50000, paid_to_account_code: "1010")
    end
  end

  describe "update_status/2" do
    test "updates consultation status" do
      consultation = consultation_fixture(%{status: "scheduled"})
      assert {:ok, updated} = Consultations.update_status(consultation, "completed")
      assert updated.status == "completed"
    end

    test "returns error for invalid status" do
      consultation = consultation_fixture()
      assert {:error, changeset} = Consultations.update_status(consultation, "invalid_status")
      assert errors_on(changeset)[:status]
    end
  end

  describe "list_payments_for_consultation/1" do
    test "returns empty list when no payments" do
      consultation = consultation_fixture()
      assert Consultations.list_payments_for_consultation(consultation) == []
    end
  end

  describe "change_consultation/2" do
    test "returns a changeset" do
      consultation = consultation_fixture()
      assert %Ecto.Changeset{} = Consultations.change_consultation(consultation, %{status: "completed"})
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
