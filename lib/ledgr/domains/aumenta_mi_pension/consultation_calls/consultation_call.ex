defmodule Ledgr.Domains.AumentaMiPension.ConsultationCalls.ConsultationCall do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "consultation_calls" do
    field :status, :string
    field :whereby_meeting_id, :string
    field :whereby_room_name, :string
    field :whereby_room_url, :string
    field :whereby_host_url, :string
    field :created_at, :naive_datetime
    field :started_at, :naive_datetime
    field :ended_at, :naive_datetime
    field :duration_seconds, :integer
    field :recording_id, :string
    field :recording_url, :string
    field :recording_status, :string
    field :transcript_text, :string
    field :transcript_json, :string
    field :transcription_status, :string

    belongs_to :consultation, Ledgr.Domains.AumentaMiPension.Consultations.Consultation
  end
end
