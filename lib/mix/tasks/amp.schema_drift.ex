defmodule Mix.Tasks.Amp.SchemaDrift do
  @shortdoc "Detect drift between AMP Ecto schemas and the live DB schema"

  @moduledoc """
  Walks every bot-owned Ecto schema registered in
  `Ledgr.Domains.AumentaMiPension.BotOwnedSchemas` and compares the fields
  declared in code against `information_schema.columns` on the live AMP
  database. Exits non-zero when a column we depend on is missing — the class of
  bug that took down prod on 2026-05-23.

  ## Usage

      AUMENTA_MI_PENSION_DATABASE_URL='postgresql://...' mix amp.schema_drift

  Designed to run in CI on every PR — see `.github/workflows/schema-drift.yml`.

  See `Ledgr.SchemaDrift` for what the [FAIL] / [INFO] / [OK] categories mean
  and why the check opens its own connection rather than booting the app.
  """

  use Mix.Task

  alias Ledgr.Domains.AumentaMiPension.BotOwnedSchemas

  @impl Mix.Task
  def run(_args) do
    # Compile so the schema modules are loaded (we need __schema__/1).
    Mix.Task.run("compile")

    "AUMENTA_MI_PENSION_DATABASE_URL"
    |> Ledgr.SchemaDrift.url_from_env!()
    |> Ledgr.SchemaDrift.run!(BotOwnedSchemas.schemas())
  end
end
