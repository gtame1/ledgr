defmodule Ledgr.Repos.HelloDoctor.Migrations.AddPrescryptoSpecialtyIdToSpecialties do
  use Ecto.Migration

  def change do
    alter table(:specialties) do
      add_if_not_exists :prescrypto_specialty_id, :integer, null: true
    end
  end
end
