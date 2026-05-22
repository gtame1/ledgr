# Demo data for the Doctor Payouts page.
#
# - Creates linked stripe_payments for any already-paid consultations from
#   the base seed.
# - Adds ~20 fresh consultations spread across May 2026 (uses the doctors
#   and patients already seeded by hello_doctor_seeds.exs).
# - Creates a mix of paid / refunded / already-paid-out scenarios so the
#   new Doctor Payouts UI has something interesting to render.
#
# Idempotent: rows are keyed on deterministic identifiers, so re-running
# only fills in what's missing.
#
# Run with: mix run priv/repos/hello_doctor/seeds/doctor_payouts_demo.exs

alias Ledgr.Repo
alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
alias Ledgr.Domains.HelloDoctor.Conversations.Conversation
alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
alias Ledgr.Domains.HelloDoctor.Patients.Patient
alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment
alias Ledgr.Domains.HelloDoctor.DoctorPayouts

Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)
Ledgr.Domain.put_current(Ledgr.Domains.HelloDoctor)

import Ecto.Query

# ── Helpers ─────────────────────────────────────────────────────

estimate_stripe_fee = fn amount_pesos ->
  # Same formula as ConsultationAccounting.estimate_stripe_fee_cents/1.
  cents = round(amount_pesos * 100)
  base = cents * 0.036 + 300
  Float.round(base * 1.16 / 100, 2)
end

upsert_stripe_payment = fn consultation, status, base_amount, paid_at ->
  amount_refunded = if status == "refunded", do: base_amount, else: 0.0
  session_id = "cs_test_demo_#{consultation.id}"

  attrs = %{
    stripe_session_id: session_id,
    stripe_payment_intent_id: "pi_test_demo_#{String.slice(consultation.id, 0..7)}",
    amount: base_amount,
    amount_refunded: amount_refunded,
    currency: "mxn",
    status: status,
    customer_email:
      "#{(consultation.patient && consultation.patient.display_name) || "patient"}@example.com",
    customer_name:
      (consultation.patient &&
         (consultation.patient.full_name || consultation.patient.display_name)) || "Patient",
    consultation_id: consultation.id,
    stripe_fee: estimate_stripe_fee.(base_amount),
    product_name: "Consulta médica",
    paid_at: paid_at
  }

  case Repo.get_by(StripePayment, stripe_session_id: session_id) do
    nil ->
      sp = Repo.insert!(StripePayment.changeset(%StripePayment{}, attrs))
      {:inserted, sp}

    existing ->
      {:existing, existing}
  end
end

# ── 1. Link stripe_payments to the base-seed paid consultations ─

base_consultations =
  from(c in Consultation,
    where: c.payment_status in ["paid", "confirmed"],
    order_by: [asc: c.assigned_at]
  )
  |> Repo.all()
  |> Repo.preload([:patient, :doctor])

if base_consultations == [] do
  IO.puts(
    "\n⚠ No paid consultations found. Run hello_doctor_seeds.exs first " <>
      "(mix run priv/repos/hello_doctor/seeds.exs)."
  )

  System.halt(1)
end

IO.puts("Linking stripe_payments for #{length(base_consultations)} base consultations…")

Enum.with_index(base_consultations)
|> Enum.each(fn {c, i} ->
  status = if i == length(base_consultations) - 1, do: "refunded", else: "paid"
  amount = c.payment_amount || 500.0
  paid_at = c.completed_at || c.assigned_at || NaiveDateTime.utc_now()

  case upsert_stripe_payment.(c, status, amount, paid_at) do
    {:inserted, _} ->
      IO.puts("  + #{String.slice(c.id, 0..7)} (#{status}, $#{amount})")

    {:existing, _} ->
      IO.puts("  = #{String.slice(c.id, 0..7)} (already linked)")
  end
end)

# ── 2. Bulk-add May 2026 consultations (deterministic IDs → idempotent) ──

doctors = Repo.all(from d in Doctor, order_by: d.created_at)
patients = Repo.all(from p in Patient, order_by: p.created_at)

if length(doctors) < 2 or length(patients) < 2 do
  IO.puts("\n⚠ Need at least 2 doctors and 2 patients (run hello_doctor_seeds.exs).")
  System.halt(1)
end

# Each entry: {day_in_may, doctor_index, patient_index, amount, status, payout_state}
#   status      ∈ "paid" | "refunded"
#   payout_state ∈ :unpaid | :paid (whether to create a doctor_payout already)
demo_rows = [
  {2, 0, 0, 500.0, "paid", :paid},
  {3, 1, 1, 800.0, "paid", :paid},
  {4, 2, 2, 600.0, "paid", :paid},
  {5, 0, 3, 500.0, "paid", :unpaid},
  {6, 1, 4, 800.0, "paid", :unpaid},
  {7, 2, 0, 600.0, "paid", :unpaid},
  {8, 3, 1, 1000.0, "paid", :unpaid},
  {9, 0, 2, 500.0, "refunded", :unpaid},
  {10, 1, 3, 800.0, "paid", :unpaid},
  {12, 2, 4, 600.0, "paid", :unpaid},
  {13, 3, 0, 1000.0, "refunded", :paid},
  {14, 0, 1, 500.0, "paid", :unpaid},
  {15, 1, 2, 800.0, "paid", :unpaid},
  {16, 2, 3, 600.0, "paid", :unpaid},
  {17, 3, 4, 1000.0, "paid", :unpaid},
  {18, 0, 0, 500.0, "paid", :unpaid},
  {19, 1, 1, 800.0, "refunded", :unpaid},
  {20, 2, 2, 600.0, "paid", :unpaid},
  {21, 3, 3, 1000.0, "paid", :unpaid},
  {22, 0, 4, 500.0, "paid", :unpaid}
]

IO.puts("\nCreating #{length(demo_rows)} May 2026 consultations…")

# Build the consultations + conversations idempotently.
may_consultations =
  Enum.map(demo_rows, fn {day, di, pi, amount, status, _payout_state} = row ->
    doctor = Enum.at(doctors, rem(di, length(doctors)))
    patient = Enum.at(patients, rem(pi, length(patients)))
    cid = "demo-may2026-#{String.pad_leading(Integer.to_string(day), 2, "0")}-#{di}-#{pi}"

    consultation =
      case Repo.get(Consultation, cid) do
        nil ->
          conv_id = "demo-conv-#{cid}"

          unless Repo.get(Conversation, conv_id) do
            Repo.insert!(
              %Conversation{}
              |> Ecto.Changeset.change(%{
                id: conv_id,
                patient_id: patient.id,
                status: "closed",
                funnel_stage: "completed",
                doctor_recommended: true,
                doctor_declined_by_patient: false
              }),
              on_conflict: :nothing
            )
          end

          assigned_at = NaiveDateTime.new!(2026, 5, day, 10, 0, 0)
          completed_at = NaiveDateTime.new!(2026, 5, day, 10, 25, 0)

          Repo.insert!(
            %Consultation{}
            |> Ecto.Changeset.change(%{
              id: cid,
              conversation_id: conv_id,
              patient_id: patient.id,
              doctor_id: doctor.id,
              status: "completed",
              payment_status: "paid",
              payment_amount: amount,
              assigned_at: assigned_at,
              accepted_at: assigned_at,
              completed_at: completed_at,
              duration_minutes: 25,
              patient_summary: "Demo consultation #{cid}"
            }),
            on_conflict: :nothing
          )

        existing ->
          existing
      end
      |> Repo.preload([:patient, :doctor])

    paid_at = NaiveDateTime.new!(2026, 5, day, 10, 5, 0)
    _ = upsert_stripe_payment.(consultation, status, amount, paid_at)
    {row, consultation}
  end)

IO.puts("  ✓ #{length(may_consultations)} consultation rows ready")

# ── 3. Create doctor_payouts for any rows marked :paid ───────────

IO.puts("\nCreating doctor_payouts for rows marked already-paid…")

# Group already-paid rows by doctor so we can show bulk payouts too.
to_pay =
  may_consultations
  |> Enum.filter(fn {{_d, _di, _pi, _a, _s, state}, _c} -> state == :paid end)
  |> Enum.group_by(fn {_, c} -> c.doctor_id end)

# Also count the FIRST base consultation as a paid-out example (preserved
# behavior from earlier seed run).
[first_base | _] = base_consultations

extra_first_base? =
  from(j in Ledgr.Domains.HelloDoctor.DoctorPayouts.DoctorPayoutConsultation,
    where: j.consultation_id == ^first_base.id,
    limit: 1
  )
  |> Repo.one()
  |> is_nil()

if extra_first_base? do
  case DoctorPayouts.create_payout(%{
         doctor_id: first_base.doctor_id,
         consultation_ids: [first_base.id],
         payout_date: Date.utc_today() |> Date.add(-1),
         amount: 100.0,
         payment_method: "spei",
         reference: "SPEI-demo-#{String.slice(first_base.id, 0..7)}",
         notes: "Demo: single-consultation payout (April)."
       }) do
    {:ok, p} ->
      IO.puts("  + payout ##{p.id} for #{String.slice(first_base.id, 0..7)} ($100, journal ##{p.journal_entry_id})")

    {:error, reason} ->
      IO.puts("  ! April base payout failed: #{inspect(reason)}")
  end
end

Enum.each(to_pay, fn {doctor_id, entries} ->
  consultation_ids = Enum.map(entries, fn {_, c} -> c.id end)

  already_paid? =
    from(j in Ledgr.Domains.HelloDoctor.DoctorPayouts.DoctorPayoutConsultation,
      where: j.consultation_id in ^consultation_ids,
      limit: 1
    )
    |> Repo.one()
    |> Kernel.!=(nil)

  if already_paid? do
    IO.puts("  = doctor #{String.slice(doctor_id, 0..7)} already has demo payouts (skipping)")
  else
    # Use bulk payouts where there are multiple consultations for one doctor —
    # exercises the multi-select path. Pick a payout date a few days after the
    # latest consultation in the batch.
    latest_day =
      entries
      |> Enum.map(fn {{day, _, _, _, _, _}, _} -> day end)
      |> Enum.max()

    payout_date = Date.new!(2026, 5, min(latest_day + 2, 22))
    amount_total = length(entries) * 100.0

    case DoctorPayouts.create_payout(%{
           doctor_id: doctor_id,
           consultation_ids: consultation_ids,
           payout_date: payout_date,
           amount: amount_total,
           payment_method: "bank_transfer",
           reference: "BULK-DEMO-#{String.slice(doctor_id, 0..7)}",
           notes: "Demo: bulk payout for May consultations."
         }) do
      {:ok, p} ->
        IO.puts(
          "  + bulk payout ##{p.id} for doctor #{String.slice(doctor_id, 0..7)} " <>
            "covering #{length(entries)} consult(s), $#{amount_total} (journal ##{p.journal_entry_id})"
        )

      {:error, reason} ->
        IO.puts("  ! bulk payout failed for #{doctor_id}: #{inspect(reason)}")
    end
  end
end)

IO.puts("\nDone. Visit /app/hello-doctor/doctor-payouts to see the result.")
IO.puts("Default date filter covers May 1–22 2026.")
