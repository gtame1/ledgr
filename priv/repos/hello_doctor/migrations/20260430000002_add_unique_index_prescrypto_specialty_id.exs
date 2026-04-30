defmodule Ledgr.Repos.HelloDoctor.Migrations.AddUniqueIndexPrescryptoSpecialtyId do
  use Ecto.Migration

  def change do
    create_if_not_exists unique_index(:specialties, [:prescrypto_specialty_id],
                           where: "prescrypto_specialty_id IS NOT NULL"
                         )
  end
end
