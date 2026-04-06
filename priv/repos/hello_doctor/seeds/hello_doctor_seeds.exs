alias Ledgr.Repo
alias Ledgr.Core.Accounting.Account

# ══════════════════════════════════════════════════════════════
# HelloDoctor Chart of Accounts (runs in dev AND prod)
# ══════════════════════════════════════════════════════════════

defmodule HDSeedHelper do
  def upsert_account(attrs) do
    case Repo.get_by(Account, code: attrs.code) do
      nil ->
        %Account{}
        |> Account.changeset(attrs)
        |> Repo.insert!()
      _existing -> :ok
    end
  end
end

hd_accounts = [
  # ── Assets ──────────────────────────────────────────────
  %{code: "1000", name: "Cash", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1010", name: "Bank - MXN", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1020", name: "Bank - USD", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1100", name: "Accounts Receivable", type: "asset", normal_balance: "debit"},
  %{code: "1200", name: "Stripe Clearing", type: "asset", normal_balance: "debit"},

  # ── Liabilities ─────────────────────────────────────────
  %{code: "2000", name: "Doctor Payable", type: "liability", normal_balance: "credit"},
  %{code: "2100", name: "Refunds Payable", type: "liability", normal_balance: "credit"},
  %{code: "2200", name: "Taxes Payable", type: "liability", normal_balance: "credit"},

  # ── Revenue ─────────────────────────────────────────────
  %{code: "4000", name: "Consultation Revenue", type: "revenue", normal_balance: "credit"},
  %{code: "4100", name: "Commission Revenue (15%)", type: "revenue", normal_balance: "credit"},
  %{code: "4200", name: "Other Revenue", type: "revenue", normal_balance: "credit"},

  # ── Expenses ────────────────────────────────────────────
  %{code: "6000", name: "Payment Processing Fees", type: "expense", normal_balance: "debit"},
  %{code: "6010", name: "Refunds Expense", type: "expense", normal_balance: "debit"},
  %{code: "6020", name: "Operating Expense", type: "expense", normal_balance: "debit"},
  %{code: "6030", name: "WhatsApp / Messaging Costs", type: "expense", normal_balance: "debit"},
  %{code: "6040", name: "Technology & Infrastructure", type: "expense", normal_balance: "debit"},
  %{code: "6050", name: "Marketing & Advertising", type: "expense", normal_balance: "debit"},
  %{code: "6060", name: "Salaries & Payroll", type: "expense", normal_balance: "debit"},
  %{code: "6099", name: "Other Expenses", type: "expense", normal_balance: "debit"},
]

hd_accounts |> Enum.each(&HDSeedHelper.upsert_account/1)
IO.puts("Seeded #{length(hd_accounts)} HelloDoctor accounts")

# ══════════════════════════════════════════════════════════════
# Dev-only sample data (skip in prod — bot owns domain data)
# ══════════════════════════════════════════════════════════════

if System.get_env("MIX_ENV") != "prod" and is_nil(System.get_env("HELLO_DOCTOR_DATABASE_URL")) do
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.Patients.Patient
  alias Ledgr.Domains.HelloDoctor.Conversations.Conversation
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation

  IO.puts("Seeding HelloDoctor dev sample data...")

  doctors =
    [
      %{id: Ecto.UUID.generate(), name: "Dr. Carlos Mendez Garcia", phone: "+525512345001", specialty: "Medicina General", cedula_profesional: "CED-12345678", university: "UNAM", years_experience: 10, email: "carlos@hellodoctor.mx", is_available: true},
      %{id: Ecto.UUID.generate(), name: "Dra. Maria Fernanda Lopez", phone: "+525512345002", specialty: "Dermatologia", cedula_profesional: "CED-23456789", university: "IPN", years_experience: 8, email: "maria@hellodoctor.mx", is_available: true},
      %{id: Ecto.UUID.generate(), name: "Dr. Alejandro Ruiz Torres", phone: "+525512345003", specialty: "Pediatria", cedula_profesional: "CED-34567890", university: "U de G", years_experience: 12, email: "alejandro@hellodoctor.mx", is_available: true},
      %{id: Ecto.UUID.generate(), name: "Dra. Sofia Ramirez Ortega", phone: "+525512345004", specialty: "Psicologia", cedula_profesional: "CED-45678901", university: "IBERO", years_experience: 6, email: "sofia@hellodoctor.mx", is_available: false}
    ]
    |> Enum.map(fn attrs ->
      Repo.insert!(%Doctor{} |> Ecto.Changeset.change(attrs), on_conflict: :nothing)
    end)

  IO.puts("  Created #{length(doctors)} doctors")

  patients =
    [
      %{id: Ecto.UUID.generate(), phone: "+525587654001", display_name: "Laura", full_name: "Laura Patricia Hernandez", date_of_birth: "1992-03-15", gender: "female"},
      %{id: Ecto.UUID.generate(), phone: "+525587654002", display_name: "Jose", full_name: "Jose Antonio Garcia", date_of_birth: "1981-07-22", gender: "male"},
      %{id: Ecto.UUID.generate(), phone: "+525587654003", display_name: "Daniela", full_name: "Daniela Rios Salazar", date_of_birth: "1998-01-10", gender: "female"},
      %{id: Ecto.UUID.generate(), phone: "+525587654004", display_name: "Miguel", full_name: "Miguel Angel Castaneda", date_of_birth: "1974-11-03", gender: "male"},
      %{id: Ecto.UUID.generate(), phone: "+525587654005", display_name: "Valentina", full_name: "Valentina Soto Flores", date_of_birth: "2007-06-20", gender: "female"}
    ]
    |> Enum.map(fn attrs ->
      Repo.insert!(%Patient{} |> Ecto.Changeset.change(attrs), on_conflict: :nothing)
    end)

  IO.puts("  Created #{length(patients)} patients")

  [p1, p2, p3, p4, p5] = patients

  conversations =
    [
      %{id: Ecto.UUID.generate(), patient_id: p1.id, status: "closed", funnel_stage: "completed", doctor_recommended: true, doctor_declined_by_patient: false},
      %{id: Ecto.UUID.generate(), patient_id: p2.id, status: "active", funnel_stage: "doctor_assigned", doctor_recommended: true, doctor_declined_by_patient: false},
      %{id: Ecto.UUID.generate(), patient_id: p3.id, status: "closed", funnel_stage: "completed", doctor_recommended: true, doctor_declined_by_patient: false},
      %{id: Ecto.UUID.generate(), patient_id: p4.id, status: "active", funnel_stage: "triage", doctor_recommended: false, doctor_declined_by_patient: false},
      %{id: Ecto.UUID.generate(), patient_id: p5.id, status: "closed", funnel_stage: "completed", doctor_recommended: true, doctor_declined_by_patient: false}
    ]
    |> Enum.map(fn attrs ->
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      Repo.insert!(%Conversation{} |> Ecto.Changeset.change(Map.merge(attrs, %{created_at: now, last_message_at: now})), on_conflict: :nothing)
    end)

  IO.puts("  Created #{length(conversations)} conversations")

  [d1, d2, d3, _d4] = doctors
  [cv1, cv2, cv3, _cv4, cv5] = conversations

  consultations =
    [
      %{id: Ecto.UUID.generate(), conversation_id: cv1.id, patient_id: p1.id, doctor_id: d1.id, status: "completed", payment_status: "paid", payment_amount: 500.0, assigned_at: ~N[2026-04-01 10:00:00], accepted_at: ~N[2026-04-01 10:05:00], completed_at: ~N[2026-04-01 10:25:00], duration_minutes: 20, doctor_notes: "Dolor de cabeza. Se receta paracetamol.", patient_summary: "Cefalea tensional"},
      %{id: Ecto.UUID.generate(), conversation_id: cv2.id, patient_id: p2.id, doctor_id: d2.id, status: "active", payment_status: "pending", payment_amount: 800.0, assigned_at: ~N[2026-04-06 14:00:00], accepted_at: ~N[2026-04-06 14:10:00]},
      %{id: Ecto.UUID.generate(), conversation_id: cv3.id, patient_id: p3.id, doctor_id: d1.id, status: "completed", payment_status: "paid", payment_amount: 500.0, assigned_at: ~N[2026-04-03 11:00:00], completed_at: ~N[2026-04-03 11:30:00], duration_minutes: 30, patient_summary: "Gripa comun"},
      %{id: Ecto.UUID.generate(), conversation_id: cv5.id, patient_id: p5.id, doctor_id: d3.id, status: "completed", payment_status: "paid", payment_amount: 600.0, assigned_at: ~N[2026-04-04 09:00:00], completed_at: ~N[2026-04-04 09:20:00], duration_minutes: 20, patient_summary: "Revision pediatrica"},
      %{id: Ecto.UUID.generate(), conversation_id: cv1.id, patient_id: p4.id, doctor_id: nil, status: "pending", payment_status: "pending", assigned_at: ~N[2026-04-06 16:00:00]}
    ]
    |> Enum.map(fn attrs ->
      Repo.insert!(%Consultation{} |> Ecto.Changeset.change(attrs), on_conflict: :nothing)
    end)

  IO.puts("  Created #{length(consultations)} consultations")
  IO.puts("HelloDoctor dev seed complete!")
else
  IO.puts("Skipping dev sample data (prod or remote DB detected)")
end
