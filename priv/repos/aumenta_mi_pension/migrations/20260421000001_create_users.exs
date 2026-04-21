defmodule Ledgr.Repos.AumentaMiPension.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:users) do
      add :email, :string, null: false
      add :name, :string
      add :password_hash, :string, null: false
      add :role, :string, default: "admin"
      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:users, [:email])
  end
end
