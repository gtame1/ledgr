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
  %{code: "1200", name: "Stripe Receivable", type: "asset", normal_balance: "debit"},

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

  # Make the first consultation a video call
  [c1, _c2, c3, _c4, _c5] = consultations

  alias Ledgr.Domains.HelloDoctor.ConsultationCalls.ConsultationCall
  alias Ledgr.Domains.HelloDoctor.Prescriptions.Prescription
  alias Ledgr.Domains.HelloDoctor.MedicalRecords.MedicalRecord

  # ── Video Calls with Transcripts ─────────────────────────
  Repo.insert!(%ConsultationCall{} |> Ecto.Changeset.change(%{
    id: Ecto.UUID.generate(),
    consultation_id: c1.id,
    status: "completed",
    whereby_meeting_id: "mtg-demo-001",
    whereby_room_name: "hellodoctor-room-001",
    whereby_room_url: "https://hellodoctor.whereby.com/room-001",
    whereby_host_url: "https://hellodoctor.whereby.com/room-001?roomKey=host123",
    created_at: ~N[2026-04-01 10:00:00],
    started_at: ~N[2026-04-01 10:05:00],
    ended_at: ~N[2026-04-01 10:25:00],
    duration_seconds: 1200,
    transcription_status: "completed",
    transcript_text: """
    [00:00] Dr. Mendez: Buenos dias Laura, soy el Dr. Carlos Mendez. Como se encuentra hoy?

    [00:15] Laura: Buenos dias doctor. Tengo un dolor de cabeza muy fuerte que no se me quita desde hace tres dias. Ya tome paracetamol pero no ayuda mucho.

    [01:02] Dr. Mendez: Entiendo. Me puede describir el dolor? Es punzante, como presion, o pulsatil?

    [01:20] Laura: Es como una presion constante, sobre todo en la frente y detras de los ojos. Empeora cuando estoy en la computadora mucho tiempo.

    [02:05] Dr. Mendez: Ha tenido nauseas, vomito, sensibilidad a la luz?

    [02:15] Laura: Un poco de sensibilidad a la luz, pero no nauseas.

    [03:00] Dr. Mendez: Cuantas horas duerme normalmente? Y ha estado bajo mucho estres ultimamente?

    [03:15] Laura: La verdad duermo como 5-6 horas. Y si, en el trabajo ha habido mucha presion.

    [04:30] Dr. Mendez: Por lo que me describe, parece una cefalea tensional, muy comun cuando hay estres y falta de sueno. Le voy a recetar ibuprofeno 400mg cada 8 horas por 3 dias, y le recomiendo dormir al menos 7-8 horas.

    [05:15] Laura: Y si no mejora?

    [05:25] Dr. Mendez: Si en 5 dias no mejora, hagamos una cita de seguimiento. Tambien le recomiendo hacer pausas de 20 minutos cuando este en la computadora.

    [06:00] Laura: Muchas gracias doctor, lo voy a hacer.

    [06:10] Dr. Mendez: Con gusto Laura. Cualquier cosa me escribe por WhatsApp. Que se mejore!
    """
  }))

  Repo.insert!(%ConsultationCall{} |> Ecto.Changeset.change(%{
    id: Ecto.UUID.generate(),
    consultation_id: c3.id,
    status: "completed",
    whereby_room_url: "https://hellodoctor.whereby.com/room-003",
    created_at: ~N[2026-04-03 11:00:00],
    started_at: ~N[2026-04-03 11:05:00],
    ended_at: ~N[2026-04-03 11:30:00],
    duration_seconds: 1500,
    transcription_status: "completed",
    transcript_text: """
    [00:00] Dr. Mendez: Hola Daniela, como te sientes?

    [00:10] Daniela: Hola doctor. Tengo mucha congestion nasal, dolor de garganta y un poco de fiebre desde ayer.

    [00:45] Dr. Mendez: Te has tomado la temperatura?

    [00:55] Daniela: Si, 37.8 grados.

    [01:20] Dr. Mendez: Tienes dolor de cuerpo, dolor de cabeza?

    [01:30] Daniela: Si, me duele todo el cuerpo y tengo escalofrios.

    [02:00] Dr. Mendez: Suena a un cuadro gripal clasico. Te voy a recetar paracetamol para la fiebre y el dolor, y un descongestionante nasal. Mucho liquido y reposo.

    [03:00] Daniela: Cuanto tiempo tarda en quitarse?

    [03:10] Dr. Mendez: Normalmente entre 5 a 7 dias. Si la fiebre sube arriba de 38.5 o aparecen otros sintomas, me escribes de inmediato.

    [03:40] Daniela: Gracias doctor!
    """
  }))

  IO.puts("  Created 2 video call records with transcripts")

  # ── Medical Records (via conversation) ───────────────────
  Repo.insert!(%MedicalRecord{} |> Ecto.Changeset.change(%{
    id: Ecto.UUID.generate(),
    conversation_id: cv1.id,
    patient_id: p1.id,
    chief_complaint: "Dolor de cabeza persistente por 3 dias",
    soap_subjective: "Paciente refiere cefalea tipo presion frontal y retroocular de 3 dias de evolucion. Empeora con uso prolongado de computadora. Duerme 5-6 horas. Estres laboral alto. Tomo paracetamol sin mejoria significativa. Leve fotosensibilidad.",
    soap_objective: "Paciente alerta, orientada. No signos de alarma neurologica. No rigidez de nuca. Pupilas isocoricas reactivas.",
    soap_assessment: "Cefalea tensional episodica. Relacionada con estres y privacion de sueno. Sin datos de alarma.",
    soap_plan: "1. Ibuprofeno 400mg c/8h x 3 dias\n2. Higiene de sueno: minimo 7-8 horas\n3. Pausas de pantalla cada 20 min\n4. Seguimiento en 5 dias si no mejora\n5. Acudir a urgencias si dolor subito intenso, rigidez de nuca, o cambios visuales",
    urgency: "low",
    possible_conditions: "Cefalea tensional, Migrana sin aura (menos probable)",
    specialty: "Medicina General",
    ai_summary: "Laura, 34 anos, consulta por cefalea tipo presion frontal de 3 dias, exacerbada por pantallas. Duerme 5-6h con alto estres laboral. Se diagnostica cefalea tensional episodica. Se prescribe ibuprofeno 400mg c/8h y medidas de higiene de sueno. Seguimiento en 5 dias.",
    created_at: ~N[2026-04-01 10:00:00],
    updated_at: ~N[2026-04-01 10:25:00]
  }))

  Repo.insert!(%MedicalRecord{} |> Ecto.Changeset.change(%{
    id: Ecto.UUID.generate(),
    conversation_id: cv3.id,
    patient_id: p3.id,
    chief_complaint: "Congestion nasal, dolor de garganta y fiebre",
    soap_subjective: "Paciente refiere congestion nasal, odinofagia y fiebre de 37.8C desde ayer. Dolor generalizado y escalofrios.",
    soap_assessment: "Infeccion de vias respiratorias superiores (gripa comun). Sin datos de complicacion.",
    soap_plan: "1. Paracetamol 500mg c/6h para fiebre y dolor\n2. Descongestionante nasal\n3. Liquidos abundantes y reposo\n4. Si fiebre >38.5C o empeora, acudir de inmediato",
    urgency: "low",
    possible_conditions: "IVRS viral (gripa comun), Faringitis",
    specialty: "Medicina General",
    ai_summary: "Daniela, 28 anos, presenta cuadro gripal de 1 dia de evolucion con congestion nasal, odinofagia, fiebre 37.8C y mialgias. Se diagnostica IVRS viral. Tratamiento sintomatico con paracetamol y descongestionante. Datos de alarma explicados.",
    created_at: ~N[2026-04-03 11:00:00],
    updated_at: ~N[2026-04-03 11:30:00]
  }))

  IO.puts("  Created 2 medical records with AI summaries")

  # ── Prescriptions ────────────────────────────────────────
  Repo.insert!(%Prescription{} |> Ecto.Changeset.change(%{
    id: Ecto.UUID.generate(),
    consultation_id: c1.id,
    patient_id: p1.id,
    doctor_id: d1.id,
    diagnosis: "Cefalea tensional episodica",
    content: "1. Ibuprofeno 400mg - Tomar 1 tableta cada 8 horas por 3 dias con alimentos\n2. Higiene de sueno - Dormir minimo 7-8 horas diarias\n3. Pausas de pantalla cada 20 minutos de trabajo",
    requires_prescription: false,
    created_at: ~N[2026-04-01 10:20:00]
  }))

  Repo.insert!(%Prescription{} |> Ecto.Changeset.change(%{
    id: Ecto.UUID.generate(),
    consultation_id: c3.id,
    patient_id: p3.id,
    doctor_id: d1.id,
    diagnosis: "Infeccion de vias respiratorias superiores",
    content: "1. Paracetamol 500mg - Tomar 1 tableta cada 6 horas para fiebre y dolor\n2. Oximetazolina nasal 0.05% - 2 disparos en cada fosa nasal cada 12 horas por 3 dias\n3. Liquidos abundantes (minimo 2L al dia)\n4. Reposo en casa por 3 dias",
    requires_prescription: true,
    created_at: ~N[2026-04-03 11:25:00]
  }))

  IO.puts("  Created 2 prescriptions")
  IO.puts("HelloDoctor dev seed complete!")
else
  IO.puts("Skipping dev sample data (prod or remote DB detected)")
end
