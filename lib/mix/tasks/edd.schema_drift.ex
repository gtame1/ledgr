defmodule Mix.Tasks.Edd.SchemaDrift do
  @shortdoc "Detect drift between Escuela de Dinero Ecto schemas and the live DB"

  @moduledoc """
  Walks every bot-owned Ecto schema registered in
  `Ledgr.Domains.EscuelaDeDinero.BotOwnedSchemas` and compares the fields
  declared in code against `information_schema.columns` on the live Escuela de
  Dinero database.

  Every table this domain reads is owned by `escuela-de-dinero-bot` and migrated
  by its Alembic, so this is the only thing standing between a bot-side column
  rename and a 500 in production.

  ## Usage

      ESCUELA_DE_DINERO_DATABASE_URL='postgresql://...' mix edd.schema_drift

  See `Ledgr.SchemaDrift` for what the [FAIL] / [INFO] / [OK] categories mean.
  """

  use Mix.Task

  alias Ledgr.Domains.EscuelaDeDinero.BotOwnedSchemas

  @impl Mix.Task
  def run(_args) do
    # Compile so the schema modules are loaded (we need __schema__/1).
    Mix.Task.run("compile")

    "ESCUELA_DE_DINERO_DATABASE_URL"
    |> Ledgr.SchemaDrift.url_from_env!()
    |> Ledgr.SchemaDrift.run!(BotOwnedSchemas.schemas())
  end
end
