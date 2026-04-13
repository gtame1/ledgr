defmodule Ledgr.Domains.HelloDoctor.Prescriptions.Prescription do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "prescriptions" do
    field :content, :string
    field :diagnosis, :string
    field :items_json, :string
    field :requires_prescription, :boolean
    field :created_at, :naive_datetime

    belongs_to :consultation, Ledgr.Domains.HelloDoctor.Consultations.Consultation
    belongs_to :patient, Ledgr.Domains.HelloDoctor.Patients.Patient
    belongs_to :doctor, Ledgr.Domains.HelloDoctor.Doctors.Doctor
  end
end
