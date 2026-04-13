defmodule Ledgr.Repos.HelloDoctor.Migrations.WidenMedicalRecordTextFields do
  use Ecto.Migration

  def change do
    # medical_records long-form fields need :text, not varchar(255)
    alter table(:medical_records) do
      modify :soap_subjective, :text
      modify :soap_objective, :text
      modify :soap_assessment, :text
      modify :soap_plan, :text
      modify :ai_summary, :text
      modify :possible_conditions, :text
      modify :chief_complaint, :text
      modify :escalation_reason, :text
    end

    # prescriptions.content can also be long
    alter table(:prescriptions) do
      modify :content, :text
      modify :items_json, :text
    end

    # consultations long-form fields
    alter table(:consultations) do
      modify :doctor_notes, :text
      modify :patient_summary, :text
      modify :patient_comment, :text
      modify :audit_json, :text
      modify :rejected_by_doctors, :text
    end

    # messages content
    alter table(:messages) do
      modify :content, :text
    end
  end
end
