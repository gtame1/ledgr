defmodule Ledgr.Domains.HelloDoctor.Patients.Patient do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @timestamps_opts [type: :naive_datetime]

  schema "patients" do
    field :phone, :string
    field :display_name, :string
    field :full_name, :string
    field :date_of_birth, :string
    field :gender, :string
    field :blood_type, :string
    field :weight_kg, :float
    field :height_cm, :float
    field :emergency_contact_name, :string
    field :emergency_contact_phone, :string
    field :insurance_provider, :string
    field :is_dependent, :boolean, default: false
    field :managed_by_id, :string
    field :relationship, :string
    field :terms_accepted, :boolean, default: false
    field :terms_accepted_at, :naive_datetime

    has_many :consultations, Ledgr.Domains.HelloDoctor.Consultations.Consultation
    has_many :conversations, Ledgr.Domains.HelloDoctor.Conversations.Conversation
    has_many :prescriptions, Ledgr.Domains.HelloDoctor.Prescriptions.Prescription
    has_many :medical_records, Ledgr.Domains.HelloDoctor.MedicalRecords.MedicalRecord

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  @required ~w[id]a
  @optional ~w[phone display_name full_name date_of_birth gender blood_type weight_kg height_cm emergency_contact_name emergency_contact_phone insurance_provider is_dependent managed_by_id relationship terms_accepted terms_accepted_at]a

  def changeset(patient, attrs) do
    patient
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
  end

  def name(%__MODULE__{full_name: full_name, display_name: display_name}) do
    full_name || display_name || "Unknown"
  end
end
