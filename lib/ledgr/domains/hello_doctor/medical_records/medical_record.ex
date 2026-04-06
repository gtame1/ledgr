defmodule Ledgr.Domains.HelloDoctor.MedicalRecords.MedicalRecord do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "medical_records" do
    field :chief_complaint, :string
    field :soap_subjective, :string
    field :soap_objective, :string
    field :soap_assessment, :string
    field :soap_plan, :string
    field :urgency, :string
    field :possible_conditions, :string
    field :specialty, :string
    field :escalation_reason, :string
    field :temperature_c, :float
    field :blood_pressure, :string
    field :heart_rate, :integer
    field :ai_summary, :string
    field :created_at, :naive_datetime
    field :updated_at, :naive_datetime

    belongs_to :conversation, Ledgr.Domains.HelloDoctor.Conversations.Conversation
    belongs_to :patient, Ledgr.Domains.HelloDoctor.Patients.Patient
  end
end
