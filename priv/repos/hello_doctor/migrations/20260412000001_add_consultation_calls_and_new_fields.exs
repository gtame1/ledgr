defmodule Ledgr.Repos.HelloDoctor.Migrations.AddConsultationCallsAndNewFields do
  use Ecto.Migration

  def change do
    # New columns on consultations (added by bot in prod)
    alter table(:consultations) do
      add_if_not_exists :stripe_payment_intent_id, :string
      add_if_not_exists :last_broadcast_at, :naive_datetime
      add_if_not_exists :rejected_by_doctors, :string
      add_if_not_exists :consultation_type, :string, default: "messaging"
    end

    # Video call records with transcripts
    create_if_not_exists table(:consultation_calls, primary_key: false) do
      add :id, :string, primary_key: true
      add :consultation_id, references(:consultations, type: :string, on_delete: :nothing), null: false
      add :status, :string, null: false
      add :whereby_meeting_id, :string
      add :whereby_room_name, :string
      add :whereby_room_url, :string
      add :whereby_host_url, :string
      add :created_at, :naive_datetime, null: false
      add :started_at, :naive_datetime
      add :ended_at, :naive_datetime
      add :duration_seconds, :integer
      add :recording_id, :string
      add :recording_url, :string
      add :recording_status, :string
      add :transcript_text, :text
      add :transcript_json, :text
      add :transcription_status, :string
    end

    create_if_not_exists index(:consultation_calls, [:consultation_id])
  end
end
