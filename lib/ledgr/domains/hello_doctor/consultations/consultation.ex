defmodule Ledgr.Domains.HelloDoctor.Consultations.Consultation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @timestamps_opts [type: :naive_datetime]

  schema "consultations" do
    field :status, :string
    field :assigned_at, :naive_datetime
    field :accepted_at, :naive_datetime
    field :completed_at, :naive_datetime
    field :duration_minutes, :integer
    field :doctor_notes, :string
    field :payment_status, :string
    field :payment_amount, :float
    field :payment_confirmed_at, :naive_datetime
    field :audit_json, :string
    field :patient_summary, :string
    field :patient_rating, :integer
    field :patient_comment, :string
    field :inactivity_ping_sent_at, :naive_datetime
    field :stripe_payment_intent_id, :string
    field :last_broadcast_at, :naive_datetime
    field :rejected_by_doctors, :string
    field :consultation_type, :string, default: "messaging"

    belongs_to :patient, Ledgr.Domains.HelloDoctor.Patients.Patient
    belongs_to :doctor, Ledgr.Domains.HelloDoctor.Doctors.Doctor
    belongs_to :conversation, Ledgr.Domains.HelloDoctor.Conversations.Conversation
    has_many :prescriptions, Ledgr.Domains.HelloDoctor.Prescriptions.Prescription
    has_many :calls, Ledgr.Domains.HelloDoctor.ConsultationCalls.ConsultationCall

    # No inserted_at/updated_at — bot uses assigned_at as creation timestamp
  end

  @statuses ~w[pending assigned active completed cancelled]
  @payment_statuses ~w[pending paid confirmed failed refunded]

  @required ~w[id conversation_id patient_id status payment_status assigned_at]a
  @optional ~w[doctor_id accepted_at completed_at duration_minutes doctor_notes payment_amount payment_confirmed_at audit_json patient_summary patient_rating patient_comment inactivity_ping_sent_at stripe_payment_intent_id last_broadcast_at rejected_by_doctors consultation_type]a

  def changeset(consultation, attrs) do
    consultation
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:patient_id)
    |> foreign_key_constraint(:doctor_id)
    |> foreign_key_constraint(:conversation_id)
  end

  def statuses, do: @statuses
  def payment_statuses, do: @payment_statuses
end
