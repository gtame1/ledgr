defmodule Ledgr.Domains.VolumeStudio.AccountingTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry
  alias Ledgr.Repo

  import Ledgr.Domains.VolumeStudio.Fixtures

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.VolumeStudio)
    Ledgr.Domain.put_current(Ledgr.Domains.VolumeStudio)
    vs_accounts_fixture()
    :ok
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp create_customer do
    unique = System.unique_integer([:positive])
    {:ok, c} = Ledgr.Core.Customers.create_customer(%{name: "C #{unique}", phone: "555#{unique}"})
    c.id
  end

  # ── Subscription Payment ─────────────────────────────────────────────

  describe "record_subscription_payment/3" do
    test "creates a balanced journal entry" do
      sub = subscription_fixture()

      {:ok, entry} = VolumeStudioAccounting.record_subscription_payment(sub, 30_000)

      assert entry.entry_type == "subscription_payment"
      assert entry.reference =~ "vs_sub_payment_#{sub.id}_"

      lines = Repo.preload(entry, :journal_lines).journal_lines
      total_debits = Enum.reduce(lines, 0, fn l, acc -> acc + l.debit_cents end)
      total_credits = Enum.reduce(lines, 0, fn l, acc -> acc + l.credit_cents end)
      assert total_debits == total_credits
      assert total_debits == 30_000
    end

    test "uses custom paid_to_account_code" do
      sub = subscription_fixture()
      {:ok, entry} = VolumeStudioAccounting.record_subscription_payment(sub, 10_000, paid_to_account_code: "1010")
      assert entry.entry_type == "subscription_payment"
    end
  end

  # ── Revenue Recognition ──────────────────────────────────────────────

  describe "recognize_subscription_revenue/2" do
    test "creates recognition journal entry" do
      sub = subscription_fixture(%{deferred_revenue_cents: 20_000})
      {:ok, entry} = VolumeStudioAccounting.recognize_subscription_revenue(sub, 5_000)

      assert entry.entry_type == "subscription_revenue_recognition"
      assert entry.reference =~ "vs_sub_recognize_#{sub.id}"
    end

    test "is idempotent for same subscription on same day" do
      sub = subscription_fixture(%{deferred_revenue_cents: 20_000})

      {:ok, entry1} = VolumeStudioAccounting.recognize_subscription_revenue(sub, 5_000)
      {:ok, entry2} = VolumeStudioAccounting.recognize_subscription_revenue(sub, 5_000)

      assert entry1.id == entry2.id
    end
  end

  # ── Consultation Payment ─────────────────────────────────────────────

  describe "record_consultation_payment/2" do
    test "creates a balanced journal entry" do
      consultation = consultation_fixture(%{amount_cents: 80_000})

      {:ok, entry} =
        VolumeStudioAccounting.record_consultation_payment(consultation, %{
          amount_cents: 80_000,
          payment_date: Date.utc_today()
        })

      assert entry.entry_type == "consultation_payment"

      lines = Repo.preload(entry, :journal_lines).journal_lines
      total_debits = Enum.reduce(lines, 0, fn l, acc -> acc + l.debit_cents end)
      total_credits = Enum.reduce(lines, 0, fn l, acc -> acc + l.credit_cents end)
      assert total_debits == total_credits
    end

    test "uses custom paid_to_account_code" do
      consultation = consultation_fixture()

      {:ok, entry} =
        VolumeStudioAccounting.record_consultation_payment(consultation, %{
          amount_cents: 50_000,
          payment_date: Date.utc_today(),
          paid_to_account_code: "1020"
        })

      assert entry.entry_type == "consultation_payment"
    end
  end

  # ── Space Rental Payment ─────────────────────────────────────────────

  describe "record_space_rental_payment/2" do
    test "creates a balanced journal entry" do
      rental = rental_fixture(%{amount_cents: 100_000})

      {:ok, entry} =
        VolumeStudioAccounting.record_space_rental_payment(rental, %{
          amount_cents: 50_000,
          payment_date: Date.utc_today()
        })

      assert entry.entry_type == "space_rental_payment"

      lines = Repo.preload(entry, :journal_lines).journal_lines
      total_debits = Enum.reduce(lines, 0, fn l, acc -> acc + l.debit_cents end)
      total_credits = Enum.reduce(lines, 0, fn l, acc -> acc + l.credit_cents end)
      assert total_debits == total_credits
      assert total_debits == 50_000
    end
  end

  # ── Partner Fee ──────────────────────────────────────────────────────

  describe "record_partner_fee/3" do
    test "creates a partner fee journal entry" do
      {:ok, entry} =
        VolumeStudioAccounting.record_partner_fee(
          999,
          10_000,
          date: Date.utc_today(),
          note: "Monthly fee"
        )

      assert entry.entry_type == "partner_fee"
    end
  end

  # ── Owed Change AP ───────────────────────────────────────────────────

  describe "record_owed_change_ap/3" do
    test "creates owed change journal entry" do
      sub = subscription_fixture()

      {:ok, entry} =
        VolumeStudioAccounting.record_owed_change_ap(sub, 5_000, date: Date.utc_today())

      assert entry.entry_type == "owed_change_ap"
    end
  end

  describe "record_change_given/4" do
    test "creates change given journal entry" do
      sub = subscription_fixture()
      cash = Accounting.get_account_by_code!("1000")

      {:ok, entry} =
        VolumeStudioAccounting.record_change_given(sub, 3_000, cash.id, date: Date.utc_today())

      assert entry.entry_type == "change_given"
    end
  end
end
