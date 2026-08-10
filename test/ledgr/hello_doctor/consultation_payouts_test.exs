defmodule Ledgr.Domains.HelloDoctor.ConsultationPayoutsTest do
  @moduledoc """
  `recompute/0` freezes the doctor share, then prunes rows whose patient has
  since been classified as a test account.

  That prune addressed `consultation_payouts.patient_id`, a column the table
  does not have — payout rows are keyed by consultation and doctor only. Every
  sweep raised 42703 *after* the freeze had already committed, so the worker
  logged a failure daily and no test row was ever pruned. These tests execute
  the real SQL, which is the only way this class of bug shows up: it is a
  column reference, invisible to anything that doesn't reach the database.
  """
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.HelloDoctor.ConsultationPayouts
  alias Ledgr.Domains.HelloDoctor.ConsultationPayouts.ConsultationPayout
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
  alias Ledgr.Domains.HelloDoctor.Conversations.Conversation
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.Patients.Patient
  alias Ledgr.Domains.HelloDoctor.TestAccounts

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
      name: "Dr. Test",
      specialty: "Cardiology",
      is_available: true,
      consultation_fee_mxn: 100
    })
  end

  defp patient_fixture(attrs \\ %{}) do
    Repo.insert!(struct(%Patient{id: uid("pat"), full_name: "Pat Test"}, attrs))
  end

  # `conversations` is bot-owned; its Ecto schema carries columns the local
  # test DB lacks, so insert an explicit column map rather than a struct.
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

    %{id: id}
  end

  defp consultation_fixture(doctor, patient, conversation) do
    Repo.insert!(%Consultation{
      id: uid("cons"),
      conversation_id: conversation.id,
      patient_id: patient.id,
      doctor_id: doctor.id,
      status: "completed",
      payment_status: "paid",
      payment_source: "stripe",
      payment_amount: 500.0,
      assigned_at: ~N[2026-06-10 12:00:00],
      completed_at: ~N[2026-06-10 12:00:00]
    })
  end

  describe "recompute/0" do
    test "runs without raising — the prune references a column that exists" do
      # The regression itself: recompute/0 used to raise Postgrex 42703 here.
      assert is_integer(ConsultationPayouts.recompute())
    end

    test "freezes a share for a normal paid consultation" do
      doctor = doctor_fixture()
      patient = patient_fixture()
      conv = conversation_fixture(patient)
      consultation = consultation_fixture(doctor, patient, conv)

      ConsultationPayouts.recompute()

      assert %ConsultationPayout{} = ConsultationPayouts.get(consultation.id)
    end

    test "prunes a frozen row whose patient is a test account" do
      test_phone = hd(TestAccounts.test_phones())

      doctor = doctor_fixture()
      patient = patient_fixture(%{phone: test_phone})
      conv = conversation_fixture(patient)
      consultation = consultation_fixture(doctor, patient, conv)

      # Freeze it directly: the INSERT…SELECT deliberately skips test patients,
      # so this stands in for a row frozen *before* the patient was classified.
      Repo.insert!(%ConsultationPayout{
        consultation_id: consultation.id,
        doctor_id: doctor.id,
        doctor_share_cents: 10_000,
        payment_source: "stripe",
        computed_at: ~N[2026-06-10 12:00:00]
      })

      assert ConsultationPayouts.get(consultation.id)

      ConsultationPayouts.recompute()

      refute ConsultationPayouts.get(consultation.id),
             "a payout for a test patient must be pruned by recompute/0"
    end

    test "leaves a non-test patient's frozen row alone" do
      doctor = doctor_fixture()
      patient = patient_fixture()
      conv = conversation_fixture(patient)
      consultation = consultation_fixture(doctor, patient, conv)

      ConsultationPayouts.recompute()
      frozen = ConsultationPayouts.get(consultation.id)
      assert frozen

      ConsultationPayouts.recompute()

      still = ConsultationPayouts.get(consultation.id)
      assert still, "a real patient's payout must survive the prune"
      # Frozen at delivery: a second sweep must not rewrite the amount.
      assert still.doctor_share_cents == frozen.doctor_share_cents
    end
  end
end
