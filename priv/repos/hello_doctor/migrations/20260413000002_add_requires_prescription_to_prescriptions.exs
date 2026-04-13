defmodule Ledgr.Repos.HelloDoctor.Migrations.AddRequiresPrescriptionToPrescriptions do
  use Ecto.Migration

  def change do
    alter table(:prescriptions) do
      add_if_not_exists :requires_prescription, :boolean
    end
  end
end
