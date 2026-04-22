defmodule Ledgr.Repos.HelloDoctor.Migrations.AddTargetedDoctorIdToConsultations do
  use Ecto.Migration

  def change do
    alter table(:consultations) do
      add_if_not_exists :targeted_doctor_id, :string
    end
  end
end
