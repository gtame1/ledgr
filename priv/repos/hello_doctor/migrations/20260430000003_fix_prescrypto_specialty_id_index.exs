defmodule Ledgr.Repos.HelloDoctor.Migrations.FixPrescryptoSpecialtyIdIndex do
  use Ecto.Migration

  def change do
    # Drop the partial index — Postgres can't use a partial index as an ON CONFLICT target
    # unless the conflict clause includes the same WHERE predicate (not supported by Ecto).
    # A regular unique index works fine here: Postgres treats NULLs as distinct, so multiple
    # rows with prescrypto_specialty_id = NULL are still allowed.
    drop_if_exists index(:specialties, [:prescrypto_specialty_id],
                     name: :specialties_prescrypto_specialty_id_index
                   )

    create_if_not_exists unique_index(:specialties, [:prescrypto_specialty_id])
  end
end
