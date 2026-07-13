defmodule Ledgr.Domains.HelloDoctor.DoctorPayoutsTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.HelloDoctor.DoctorPayouts
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
  alias Ledgr.Domains.HelloDoctor.Conversations.Conversation
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.Patients.Patient
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)
    Ledgr.Domain.put_current(Ledgr.Domains.HelloDoctor)
    :ok
  end

  # Window comfortably around the fixtures' June 2026 billing dates.
  @start_date ~D[2026-06-01]
  @end_date ~D[2026-06-30]

  defp uid(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"

  defp doctor_fixture do
    Repo.insert!(%Doctor{
      id: uid("doc"),
      phone: uid("phone"),
      name: "Dr. Test",
      specialty: "Cardiology",
      is_available: true
    })
  end

  defp patient_fixture do
    Repo.insert!(%Patient{id: uid("pat"), full_name: "Pat Test"})
  end

  # Inserted via insert_all with an explicit column map: `conversations` is
  # bot-owned, and its Ecto schema carries columns (quality_signal, …) that the
  # local test DB doesn't have, so a full struct insert would fail.
  defp conversation_fixture(patient) do
    id = uid("conv")
    now = ~N[2026-06-10 12:00:00]

    {1, _} =
      Repo.insert_all(Conversation, [
        %{
          id: id,
          patient_id: patient.id,
          status: "active",
          funnel_stage: "converted",
          doctor_recommended: true,
          doctor_declined_by_patient: false,
          created_at: now,
          last_message_at: now,
          tenant: "mvp",
          payment_source: "stripe"
        }
      ])

    %{id: id, tenant: "mvp"}
  end

  defp consultation_fixture(doctor, patient, conversation, attrs) do
    base = %Consultation{
      id: uid("cons"),
      conversation_id: conversation.id,
      patient_id: patient.id,
      doctor_id: doctor.id,
      status: "completed",
      payment_status: "paid",
      payment_source: "stripe",
      assigned_at: ~N[2026-06-10 12:00:00],
      completed_at: ~N[2026-06-10 12:00:00]
    }

    Repo.insert!(struct(base, attrs))
  end

  defp stripe_payment_fixture(attrs) do
    base = %StripePayment{
      stripe_session_id: uid("cs"),
      amount: 500.0,
      status: "paid",
      currency: "mxn",
      paid_at: ~N[2026-06-10 12:00:00]
    }

    Repo.insert!(struct(base, attrs))
  end

  describe "list_consultations_with_payouts/3 stripe dedup (regression)" do
    test "collapses two HARD-linked stripe rows to a single consultation row" do
      doctor = doctor_fixture()
      patient = patient_fixture()
      conversation = conversation_fixture(patient)
      consultation = consultation_fixture(doctor, patient, conversation, %{})

      # Two stripe_payments both hard-linked to the same consultation. Only
      # `stripe_session_id` is unique, so nothing at the DB level forbids this.
      # The non-paid row carries a different amount so a wrong pick is visible.
      stripe_payment_fixture(%{
        consultation_id: consultation.id,
        status: "paid",
        amount: 500.0,
        paid_at: ~N[2026-06-10 12:00:00]
      })

      stripe_payment_fixture(%{
        consultation_id: consultation.id,
        status: "failed",
        amount: 123.0,
        paid_at: ~N[2026-06-11 12:00:00]
      })

      rows = DoctorPayouts.list_consultations_with_payouts(@start_date, @end_date)
      mine = Enum.filter(rows, &(&1.consultation_id == consultation.id))

      # Before the fix this returned two rows (one per join match).
      assert length(mine) == 1
      [row] = mine

      # Dedup prefers the `paid` row over the `failed` one → amount 500, not 123.
      assert row.amount == 500.0
      assert row.stripe_synced?

      # And summarize/1 counts the billed amount exactly once.
      assert DoctorPayouts.summarize(mine).total_billed == 500.0
    end

    test "collapses two SOFT (payment-intent fallback) stripe rows to one row" do
      doctor = doctor_fixture()
      patient = patient_fixture()
      conversation = conversation_fixture(patient)
      intent = uid("pi")

      consultation =
        consultation_fixture(doctor, patient, conversation, %{stripe_payment_intent_id: intent})

      # Two stripe rows with NULL consultation_id sharing the consultation's
      # payment_intent — the soft-match arm that can also fan out.
      stripe_payment_fixture(%{
        consultation_id: nil,
        stripe_payment_intent_id: intent,
        status: "paid",
        amount: 500.0,
        paid_at: ~N[2026-06-10 12:00:00]
      })

      stripe_payment_fixture(%{
        consultation_id: nil,
        stripe_payment_intent_id: intent,
        status: "refunded",
        amount: 500.0,
        amount_refunded: 500.0,
        paid_at: ~N[2026-06-09 12:00:00]
      })

      rows = DoctorPayouts.list_consultations_with_payouts(@start_date, @end_date)
      mine = Enum.filter(rows, &(&1.consultation_id == consultation.id))

      assert length(mine) == 1
      [row] = mine
      # Prefers the `paid` row (no refund) over the refunded duplicate.
      assert row.amount == 500.0
      refute row.refunded?
      assert DoctorPayouts.summarize(mine).total_billed == 500.0
    end

    test "single stripe row is unaffected (baseline)" do
      doctor = doctor_fixture()
      patient = patient_fixture()
      conversation = conversation_fixture(patient)
      consultation = consultation_fixture(doctor, patient, conversation, %{})

      stripe_payment_fixture(%{consultation_id: consultation.id, amount: 350.0})

      rows = DoctorPayouts.list_consultations_with_payouts(@start_date, @end_date)
      mine = Enum.filter(rows, &(&1.consultation_id == consultation.id))

      assert length(mine) == 1
      assert hd(mine).amount == 350.0
    end
  end
end
