defmodule Ledgr.Repos.HelloDoctor.Migrations.AddPrescryptoToDoctors do
  use Ecto.Migration

  def change do
    alter table(:doctors) do
      add_if_not_exists :prescrypto_medic_id, :integer
      add_if_not_exists :prescrypto_token, :string
      add_if_not_exists :prescrypto_specialty_no, :string
      add_if_not_exists :prescrypto_specialty_verified, :boolean, default: false
      add_if_not_exists :prescrypto_synced_at, :utc_datetime
    end
  end
end
