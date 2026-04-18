defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateDoctorAssistantMessages do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:doctor_assistant_messages, primary_key: false) do
      add :id, :string, primary_key: true
      add :doctor_id, references(:doctors, type: :string, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :consultation_id, references(:consultations, type: :string, on_delete: :nilify_all)
      add :tool_name, :string
      add :tool_args, :text
      timestamps(inserted_at: :created_at, updated_at: false)
    end

    create_if_not_exists index(:doctor_assistant_messages, [:doctor_id])
    create_if_not_exists index(:doctor_assistant_messages, [:consultation_id])
  end
end
