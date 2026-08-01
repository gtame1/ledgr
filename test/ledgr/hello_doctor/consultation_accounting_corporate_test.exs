defmodule Ledgr.Domains.HelloDoctor.ConsultationAccountingCorporateTest do
  @moduledoc """
  Corporate (employer-paid) consultations have no Stripe checkout, so the
  Stripe JE path never runs. These tests pin the substitute entries posted by
  `ConsultationAccounting.record_corporate_payment/1`:

    * revenue recognized against a receivable (Dr 1100 / Cr 4000),
    * doctor's tenant-aware share reclassified to payable (Dr 4000 / Cr 2000),
    * idempotent re-posting,
    * and — the whole point — account 2000 nets to zero once the doctor is paid.
  """
  use Ledgr.DataCase, async: true
  import Ecto.Query

  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting
  alias Ledgr.Domains.HelloDoctor.DoctorPayouts
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
  alias Ledgr.Domains.HelloDoctor.Conversations.Conversation
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.Patients.Patient

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)
    Ledgr.Domain.put_current(Ledgr.Domains.HelloDoctor)
    :ok
  end

  defp uid(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"

  defp doctor_fixture(attrs \\ %{}) do
    Repo.insert!(
      struct(
        %Doctor{
          id: uid("doc"),
          phone: uid("phone"),
          name: "Dr. Corporate",
          specialty: "Cardiology",
          is_available: true,
          has_correct_rfc: true
        },
        attrs
      )
    )
  end

  defp patient_fixture do
    Repo.insert!(%Patient{id: uid("pat"), full_name: "Employee One"})
  end

  # `conversations` is bot-owned; insert via insert_all with an explicit column
  # map (its Ecto schema has columns the local test DB lacks).
  defp conversation_fixture(patient, tenant) do
    id = uid("conv")
    now = ~N[2026-07-16 12:00:00]

    {1, _} =
      Repo.insert_all(Conversation, [
        %{
          id: id,
          patient_id: patient.id,
          status: "active",
          funnel_stage: "converted",
          created_at: now,
          last_message_at: now,
          tenant: tenant,
          payment_source: "corporate"
        }
      ])

    %{id: id, tenant: tenant}
  end

  defp corporate_consultation_fixture(doctor, patient, conversation, attrs \\ %{}) do
    base = %Consultation{
      id: uid("cons"),
      conversation_id: conversation.id,
      patient_id: patient.id,
      doctor_id: doctor.id,
      status: "completed",
      payment_status: "confirmed",
      payment_source: "corporate",
      payment_amount: 135.0,
      corporate_account_id: uid("corp"),
      stripe_payment_intent_id: uid("corp_pi"),
      assigned_at: ~N[2026-07-16 12:00:00],
      completed_at: ~N[2026-07-16 12:00:00]
    }

    Repo.insert!(struct(base, attrs))
  end

  # Net (debit − credit) balance in cents for an account code.
  defp net_cents(code) do
    from(jl in Accounting.JournalLine,
      join: a in Accounting.Account,
      on: a.id == jl.account_id,
      where: a.code == ^code,
      select: {coalesce(sum(jl.debit_cents), 0), coalesce(sum(jl.credit_cents), 0)}
    )
    |> Repo.one()
    |> then(fn {d, c} -> d - c end)
  end

  test "posts revenue + doctor-payable entries for a corporate consult" do
    doctor = doctor_fixture()
    patient = patient_fixture()
    conversation = conversation_fixture(patient, "mvp")
    consult = corporate_consultation_fixture(doctor, patient, conversation)

    assert {:ok, entry} = ConsultationAccounting.record_corporate_payment(consult)
    assert entry.entry_type == "corporate_consultation"
    assert entry.reference == "Corporate consultation #{consult.id}"
    # Dated at the MX completion date, not today.
    assert entry.date == ~D[2026-07-16]

    entry = Repo.preload(entry, journal_lines: :account)
    by_code = Map.new(entry.journal_lines, &{&1.account.code, &1})

    # Revenue recognition against a receivable — billed rate $135.
    assert by_code["1100"].debit_cents == 13_500
    assert by_code["1100"].credit_cents == 0

    # Doctor's flat mvp share ($100) reclassified out of revenue into payable;
    # 4000 nets to the $35 HD corporate margin (135 credit − 100 debit).
    assert net_cents("4000") == -3_500
    assert net_cents("1100") == 13_500
    assert net_cents("2000") == -10_000
  end

  test "uses the doctor's negotiated fee for a direct-tenant corporate consult" do
    doctor = doctor_fixture(%{consultation_fee_mxn: 250})
    patient = patient_fixture()
    conversation = conversation_fixture(patient, "direct")
    consult = corporate_consultation_fixture(doctor, patient, conversation)

    assert {:ok, _entry} = ConsultationAccounting.record_corporate_payment(consult)

    # Direct tenant → the doctor's own $250 fee is the share; 2000 is credited
    # the full $250. 4000 nets to a $115 DEBIT (net_cents is debit−credit):
    # $250 share debited − $135 revenue credited — HD books a loss on this
    # consult because the doctor's fee exceeds what the employer was billed.
    assert net_cents("2000") == -25_000
    assert net_cents("4000") == 25_000 - 13_500
  end

  test "is idempotent — a second call posts nothing new" do
    doctor = doctor_fixture()
    patient = patient_fixture()
    conversation = conversation_fixture(patient, "mvp")
    consult = corporate_consultation_fixture(doctor, patient, conversation)

    assert {:ok, %Accounting.JournalEntry{}} =
             ConsultationAccounting.record_corporate_payment(consult)

    assert {:ok, :already_posted} =
             ConsultationAccounting.record_corporate_payment(consult)

    # Still exactly one credit of $100 to Doctor Payable.
    assert net_cents("2000") == -10_000
  end

  test "account 2000 nets to zero after the corporate consult is paid out" do
    doctor = doctor_fixture()
    patient = patient_fixture()
    conversation = conversation_fixture(patient, "mvp")
    consult = corporate_consultation_fixture(doctor, patient, conversation)

    assert {:ok, _} = ConsultationAccounting.record_corporate_payment(consult)
    assert net_cents("2000") == -10_000

    # Pay the doctor: $100 share = $97.50 cash + $2.50 ISR (2.5% w/ correct RFC).
    assert {:ok, _payout} =
             DoctorPayouts.create_payout(%{
               doctor_id: doctor.id,
               consultation_ids: [consult.id],
               payout_date: ~D[2026-08-01],
               amount_cents: 9_750,
               isr_retention_cents: 250,
               iva_retention_cents: 0,
               payment_method: "bank_transfer",
               reference: "test corporate payout"
             })

    # Corporate JE credited 2000 by $100; the payout debited it by the same
    # $100 gross (cash + ISR) → nets to zero.
    assert net_cents("2000") == 0
  end

  test "backfill posts entries for eligible corporate consults and skips others" do
    doctor = doctor_fixture()
    patient = patient_fixture()

    conv_ok = conversation_fixture(patient, "mvp")
    ok = corporate_consultation_fixture(doctor, patient, conv_ok)

    # Cancelled corporate consult — never happened, so no revenue/payable.
    conv_cancelled = conversation_fixture(patient, "mvp")

    cancelled =
      corporate_consultation_fixture(doctor, patient, conv_cancelled, %{status: "cancelled"})

    assert {:ok, %{posted: 1, skipped: 0, errors: 0}} =
             ConsultationAccounting.backfill_corporate_journal_entries()

    assert Repo.exists?(
             from(je in Accounting.JournalEntry,
               where: je.reference == ^"Corporate consultation #{ok.id}"
             )
           )

    refute Repo.exists?(
             from(je in Accounting.JournalEntry,
               where: je.reference == ^"Corporate consultation #{cancelled.id}"
             )
           )

    # Re-running is a no-op.
    assert {:ok, %{posted: 0, skipped: 1, errors: 0}} =
             ConsultationAccounting.backfill_corporate_journal_entries()
  end
end
