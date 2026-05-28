defmodule Ledgr.Repos.HelloDoctor.Migrations.AddDeactivatedAtToDoctors do
  use Ecto.Migration

  # The bot's tooling has already added this column to prod, so the
  # `if not exists` guard makes this a no-op there. The migration exists
  # to give dev / test environments the same column without diverging.
  def change do
    alter table(:doctors) do
      add_if_not_exists :deactivated_at, :utc_datetime
    end
  end
end
