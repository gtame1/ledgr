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

    belongs_to :patient, Ledgr.Domains.HelloDoctor.Patients.Patient
    has_many :consultations, Ledgr.Domains.HelloDoctor.Consultations.Consultation
    has_many :messages, Ledgr.Domains.HelloDoctor.Messages.Message
    has_one :medical_record, Ledgr.Domains.HelloDoctor.MedicalRecords.MedicalRecord
  end
end
