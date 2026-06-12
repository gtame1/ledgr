defmodule Ledgr.Domains.HelloDoctor.Conversations.Conversation do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "conversations" do
    field :status, :string
    field :funnel_stage, :string
    field :resolved_without_doctor, :boolean
    field :doctor_recommended, :boolean
    field :doctor_declined_by_patient, :boolean
    field :created_at, :naive_datetime
    field :last_message_at, :naive_datetime
    field :stripe_payment_intent_id, :string
    field :consultation_type, :string
    # Bot-owned. Values seen today: "mvp" (the bot-routed / on-demand
    # flow). "direct" is reserved for the upcoming patient-picks-doctor
    # flow, where the doctor's own consultation_fee_mxn drives pricing.
    field :tenant, :string
    # Bot-owned (ADR-046). One of "stripe" (default — patient-paid via
    # Stripe), "corporate" (employer-paid, no Stripe charge), or "test"
    # (the /prueba bypass — not doctor-payable).
    field :payment_source, :string, default: "stripe"
    # Bot-owned. References corporate_accounts.id when payment_source =
    # "corporate"; NULL otherwise. The monthly-invoice join key.
    field :corporate_account_id, :string

    # Bot-owned (bot ADR-019/ADR-059): operator quality marks + live case
    # notes. Read directly for display; ALL writes go through the bot's
    # admin API (BotAdmin.mark_conversation / set_operator_notes) — never
    # write these columns from Ecto. TIMESTAMPTZ columns read as
    # :utc_datetime (unlike the table's naive created_at).
    field :quality_signal, :string
    field :corpus_candidate, :boolean, default: false
    field :quality_marked_at, :utc_datetime
    field :quality_marked_by, :string
    field :quality_notes, :string
    field :failure_category, :string
    field :first_bad_message_id, :string
    field :exemplary_message_id, :string
    field :corrected_response, :string
    field :operator_notes, :string
    field :operator_notes_updated_at, :utc_datetime
    field :operator_notes_updated_by, :string

    belongs_to :patient, Ledgr.Domains.HelloDoctor.Patients.Patient
    has_many :consultations, Ledgr.Domains.HelloDoctor.Consultations.Consultation
    has_many :messages, Ledgr.Domains.HelloDoctor.Messages.Message
    has_one :medical_record, Ledgr.Domains.HelloDoctor.MedicalRecords.MedicalRecord
  end
end
