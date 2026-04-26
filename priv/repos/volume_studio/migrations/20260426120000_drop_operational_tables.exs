defmodule Ledgr.Repos.VolumeStudio.Migrations.DropOperationalTables do
  use Ecto.Migration

  def up do
    drop_if_exists table(:class_bookings)
    drop_if_exists table(:class_sessions)

    alter table(:consultations) do
      remove :instructor_id
      add :instructor_name, :string
    end

    drop_if_exists table(:instructors)
  end

  def down do
    raise Ecto.MigrationError,
      message: "Irreversible: operational tables removed in Phase 2 of Volume Studio refactor."
  end
end
