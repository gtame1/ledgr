defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateHelloDoctorSchema do
  use Ecto.Migration

  @doc """
  Creates all HelloDoctor tables using IF NOT EXISTS.

  - In dev: creates everything (bot tables + ledgr tables) from scratch.
  - In prod: bot tables already exist and are skipped; only ledgr-specific
    tables (accounts, journal_entries, journal_lines, users) are created.
  """
  def change do
    # ── Bot domain tables (owned by WhatsApp bot in prod) ───────────

    create_if_not_exists table(:doctors, primary_key: false) do
      add :id, :string, primary_key: true
      add :phone, :string, null: false
      add :name, :string, null: false
      add :specialty, :string, null: false
      add :cedula_profesional, :string
      add :university, :string
      add :years_experience, :integer
      add :email, :string
      add :is_available, :boolean, null: false, default: true
      add :created_at, :naive_datetime, null: false, default: fragment("now()")
    end
    create_if_not_exists unique_index(:doctors, [:phone])

    create_if_not_exists table(:patients, primary_key: false) do
      add :id, :string, primary_key: true
      add :phone, :string
      add :display_name, :string
      add :full_name, :string
      add :date_of_birth, :string
      add :gender, :string
      add :blood_type, :string
      add :weight_kg, :float
      add :height_cm, :float
      add :emergency_contact_name, :string
      add :emergency_contact_phone, :string
      add :insurance_provider, :string
      add :is_dependent, :boolean, default: false
      add :managed_by_id, :string
      add :relationship, :string
      add :terms_accepted, :boolean, default: false
      add :terms_accepted_at, :naive_datetime
      add :created_at, :naive_datetime, null: false, default: fragment("now()")
      add :updated_at, :naive_datetime, null: false, default: fragment("now()")
    end

    create_if_not_exists table(:conversations, primary_key: false) do
      add :id, :string, primary_key: true
      add :patient_id, references(:patients, type: :string, on_delete: :nothing), null: false
      add :status, :string, null: false
      add :funnel_stage, :string, null: false
      add :resolved_without_doctor, :boolean
      add :doctor_recommended, :boolean, null: false, default: false
      add :doctor_declined_by_patient, :boolean, null: false, default: false
      add :created_at, :naive_datetime, null: false, default: fragment("now()")
      add :last_message_at, :naive_datetime, null: false, default: fragment("now()")
    end

    create_if_not_exists table(:consultations, primary_key: false) do
      add :id, :string, primary_key: true
      add :conversation_id, references(:conversations, type: :string, on_delete: :nothing), null: false
      add :patient_id, references(:patients, type: :string, on_delete: :nothing), null: false
      add :doctor_id, references(:doctors, type: :string, on_delete: :nothing)
      add :status, :string, null: false
      add :assigned_at, :naive_datetime, null: false, default: fragment("now()")
      add :accepted_at, :naive_datetime
      add :completed_at, :naive_datetime
      add :duration_minutes, :integer
      add :doctor_notes, :string
      add :payment_status, :string, null: false, default: "pending"
      add :payment_amount, :float
      add :payment_confirmed_at, :naive_datetime
      add :audit_json, :string
      add :patient_summary, :string
      add :patient_rating, :integer
      add :patient_comment, :string
      add :inactivity_ping_sent_at, :naive_datetime
    end

    create_if_not_exists table(:messages, primary_key: false) do
      add :id, :string, primary_key: true
      add :conversation_id, references(:conversations, type: :string, on_delete: :nothing), null: false
      add :role, :string, null: false
      add :content, :string, null: false
      add :message_type, :string, null: false
      add :created_at, :naive_datetime, null: false, default: fragment("now()")
    end

    create_if_not_exists table(:prescriptions, primary_key: false) do
      add :id, :string, primary_key: true
      add :consultation_id, references(:consultations, type: :string, on_delete: :nothing), null: false
      add :patient_id, references(:patients, type: :string, on_delete: :nothing), null: false
      add :doctor_id, references(:doctors, type: :string, on_delete: :nothing), null: false
      add :content, :string, null: false
      add :diagnosis, :string
      add :items_json, :string
      add :created_at, :naive_datetime, null: false, default: fragment("now()")
    end

    create_if_not_exists table(:medical_records, primary_key: false) do
      add :id, :string, primary_key: true
      add :conversation_id, references(:conversations, type: :string, on_delete: :nothing), null: false
      add :patient_id, references(:patients, type: :string, on_delete: :nothing), null: false
      add :chief_complaint, :string
      add :soap_subjective, :string
      add :soap_objective, :string
      add :soap_assessment, :string
      add :soap_plan, :string
      add :urgency, :string
      add :possible_conditions, :string
      add :specialty, :string
      add :escalation_reason, :string
      add :temperature_c, :float
      add :blood_pressure, :string
      add :heart_rate, :integer
      add :ai_summary, :string
      add :created_at, :naive_datetime, null: false, default: fragment("now()")
      add :updated_at, :naive_datetime, null: false, default: fragment("now()")
    end

    create_if_not_exists table(:patient_allergies, primary_key: false) do
      add :id, :string, primary_key: true
      add :patient_id, references(:patients, type: :string, on_delete: :nothing), null: false
      add :allergy, :string, null: false
      add :severity, :string
      add :created_at, :naive_datetime, null: false, default: fragment("now()")
    end

    create_if_not_exists table(:patient_conditions, primary_key: false) do
      add :id, :string, primary_key: true
      add :patient_id, references(:patients, type: :string, on_delete: :nothing), null: false
      add :condition, :string, null: false
      add :severity, :string
      add :created_at, :naive_datetime, null: false, default: fragment("now()")
    end

    create_if_not_exists table(:patient_medications, primary_key: false) do
      add :id, :string, primary_key: true
      add :patient_id, references(:patients, type: :string, on_delete: :nothing), null: false
      add :medication, :string, null: false
      add :dosage, :string
      add :created_at, :naive_datetime, null: false, default: fragment("now()")
    end

    # ── Ledgr-specific tables ───────────────────────────────────────

    create_if_not_exists table(:accounts) do
      add :code, :string, null: false
      add :name, :string, null: false
      add :type, :string, null: false
      add :normal_balance, :string, null: false
      add :is_cash, :boolean, default: false
      add :is_cogs, :boolean, default: false
      timestamps()
    end
    create_if_not_exists unique_index(:accounts, [:code])

    create_if_not_exists table(:journal_entries) do
      add :date, :date, null: false
      add :description, :string, null: false
      add :entry_type, :string
      add :reference, :string
      add :payee, :string
      timestamps()
    end

    create_if_not_exists table(:journal_lines) do
      add :journal_entry_id, references(:journal_entries, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :debit_cents, :integer, default: 0
      add :credit_cents, :integer, default: 0
      add :description, :string
      timestamps()
    end
    create_if_not_exists index(:journal_lines, [:journal_entry_id])
    create_if_not_exists index(:journal_lines, [:account_id])

    create_if_not_exists table(:app_settings) do
      add :key, :string, null: false
      add :value, :string
      timestamps()
    end
    create_if_not_exists unique_index(:app_settings, [:key])

    create_if_not_exists table(:users) do
      add :email, :string, null: false
      add :name, :string
      add :password_hash, :string, null: false
      add :role, :string, default: "admin"
      timestamps(type: :utc_datetime)
    end
    create_if_not_exists unique_index(:users, [:email])
  end
end
