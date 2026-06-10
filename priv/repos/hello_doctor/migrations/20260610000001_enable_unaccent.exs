defmodule Ledgr.Repos.HelloDoctor.Migrations.EnableUnaccent do
  use Ecto.Migration

  @moduledoc """
  Enables the `unaccent` Postgres extension on the HelloDoctor DB so
  the acquisition dashboard can match patient messages
  accent-insensitively (e.g. `médico` ↔ `medico`, `podrían` ↔ `podrian`).
  Already enabled on prod (Neon) via direct CREATE EXTENSION; this
  keeps local dev DBs in sync.
  """

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS unaccent")
  end

  def down do
    # Other code may rely on the function being available — don't drop.
    :ok
  end
end
