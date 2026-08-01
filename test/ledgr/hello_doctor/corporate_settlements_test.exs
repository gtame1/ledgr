defmodule Ledgr.Domains.HelloDoctor.CorporateSettlementsTest do
  @moduledoc """
  The employer-payment (collection) leg that clears the receivable a corporate
  consult books: `Dr Bank / Cr 1100 A/R`. Pins the booked-AR computation, the
  settlement entry, idempotency, partial pays, and that 1100 zeroes out once
  the full receivable is settled.
  """
  use Ledgr.DataCase, async: true
  import Ecto.Query

  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting
  alias Ledgr.Domains.HelloDoctor.CorporateSettlements
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

  defp doctor_fixture do
    Repo.insert!(%Doctor{
      id: uid("doc"),
      phone: uid("phone"),
      name: "Dr. Corp",
      specialty: "Cardiology",
      is_available: true,
      has_correct_rfc: true
    })
  end

  defp patient_fixture, do: Repo.insert!(%Patient{id: uid("pat"), full_name: "Employee"})

  defp conversation_fixture(patient) do
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
          tenant: "mvp",
          payment_source: "corporate"
        }
      ])

    %{id: id}
  end

  # A corporate consult completed on 2026-07-16 (Mexico City) with a booked
  # rate of $135, plus its AR journal entry already posted.
  defp corporate_consult_with_ar(account_id, attrs \\ %{}) do
    doctor = doctor_fixture()
    patient = patient_fixture()
    conversation = conversation_fixture(patient)

    consult =
      Repo.insert!(
        struct(
          %Consultation{
            id: uid("cons"),
            conversation_id: conversation.id,
            patient_id: patient.id,
            doctor_id: doctor.id,
            status: "completed",
            payment_status: "confirmed",
            payment_source: "corporate",
            payment_amount: 135.0,
            corporate_account_id: account_id,
            stripe_payment_intent_id: uid("corp_pi"),
            assigned_at: ~N[2026-07-16 12:00:00],
            completed_at: ~N[2026-07-16 12:00:00]
          },
          attrs
        )
      )

    {:ok, _} = ConsultationAccounting.record_corporate_payment(consult)
    consult
  end

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

  test "booked_ar_cents sums the month's eligible corporate consults" do
    account_id = uid("corp")
    corporate_consult_with_ar(account_id)
    corporate_consult_with_ar(account_id)

    assert CorporateSettlements.booked_ar_cents(account_id, "2026-07") == 27_000
    # A different month has nothing booked.
    assert CorporateSettlements.booked_ar_cents(account_id, "2026-06") == 0
  end

  test "booked_ar_cents excludes cancelled consults" do
    account_id = uid("corp")
    corporate_consult_with_ar(account_id)
    corporate_consult_with_ar(account_id, %{status: "cancelled"})

    # Only the completed one counts (the cancelled consult books no AR either).
    assert CorporateSettlements.booked_ar_cents(account_id, "2026-07") == 13_500
  end

  test "recording a full settlement clears the receivable to zero" do
    account_id = uid("corp")
    corporate_consult_with_ar(account_id)

    assert net_cents("1100") == 13_500

    assert {:ok, entry} =
             CorporateSettlements.record_settlement("acme", "2026-07", %{
               amount_cents: 13_500,
               date: ~D[2026-08-01],
               deposit_code: "1010",
               account_name: "Acme"
             })

    assert entry.entry_type == "corporate_settlement"
    assert entry.reference == "Corporate settlement — acme 2026-07"

    # Receivable cleared; the cash landed in Bank-MXN.
    assert net_cents("1100") == 0
    assert net_cents("1010") == 13_500
  end

  test "a partial settlement leaves the residual receivable outstanding" do
    account_id = uid("corp")
    corporate_consult_with_ar(account_id)

    assert {:ok, _} =
             CorporateSettlements.record_settlement("acme", "2026-07", %{
               amount_cents: 10_000,
               date: ~D[2026-08-01],
               deposit_code: "1010",
               account_name: "Acme"
             })

    # $100 of the $135 receivable collected; $35 still outstanding in 1100.
    assert net_cents("1100") == 3_500
    assert net_cents("1010") == 10_000
  end

  test "is idempotent — one settlement per (slug, month)" do
    account_id = uid("corp")
    corporate_consult_with_ar(account_id)

    assert {:ok, entry} =
             CorporateSettlements.record_settlement("acme", "2026-07", %{
               amount_cents: 13_500,
               date: ~D[2026-08-01],
               account_name: "Acme"
             })

    assert CorporateSettlements.settled?("acme", "2026-07")
    assert CorporateSettlements.settlement_amount_cents(entry) == 13_500

    assert {:error, :already_settled} =
             CorporateSettlements.record_settlement("acme", "2026-07", %{
               amount_cents: 13_500,
               date: ~D[2026-08-01],
               account_name: "Acme"
             })
  end

  test "rejects a non-positive amount" do
    assert {:error, :invalid_amount} =
             CorporateSettlements.record_settlement("acme", "2026-07", %{
               amount_cents: 0,
               date: ~D[2026-08-01],
               account_name: "Acme"
             })
  end

  test "defaults an unknown deposit account to Bank-MXN (1010)" do
    account_id = uid("corp")
    corporate_consult_with_ar(account_id)

    assert {:ok, _} =
             CorporateSettlements.record_settlement("acme", "2026-07", %{
               amount_cents: 13_500,
               date: ~D[2026-08-01],
               deposit_code: "9999",
               account_name: "Acme"
             })

    assert net_cents("1010") == 13_500
  end
end
