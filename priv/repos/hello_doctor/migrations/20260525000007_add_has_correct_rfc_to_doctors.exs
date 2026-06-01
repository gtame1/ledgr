defmodule Ledgr.Repos.HelloDoctor.Migrations.AddHasCorrectRfcToDoctors do
  use Ecto.Migration

  # Admin-managed boolean — checked off once we've verified we have the
  # doctor's correct RFC on file (for invoicing / retention CFDIs).
  # add_if_not_exists so this is a no-op in any env where the bot tooling
  # has already created the column.
  def change do
    alter table(:doctors) do
      add_if_not_exists :has_correct_rfc, :boolean, default: false, null: false
    end
  end
end
