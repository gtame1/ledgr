defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateAppSettings do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:app_settings) do
      add :key, :string, null: false
      add :value, :string
      timestamps()
    end
    create_if_not_exists unique_index(:app_settings, [:key])
  end
end
