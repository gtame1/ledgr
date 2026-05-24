defmodule Mix.Tasks.Amp.SchemaDrift do
  @shortdoc "Detect drift between AMP Ecto schemas and the live DB schema"

  @moduledoc """
  Walks every bot-owned Ecto schema registered in
  `Ledgr.Domains.AumentaMiPension.BotOwnedSchemas` and compares the
  fields declared in code against `information_schema.columns` on the
  live AMP database. Exits non-zero when a column we depend on is
  missing — the class of bug that took down prod on 2026-05-23.

  ## Categories

    * **[FAIL]** `missing_in_db` — the schema declares a field the DB
      doesn't have. Every `SELECT` against that table will crash with
      `undefined_column`. Update the schema (remove the field) before
      shipping.

    * **[INFO]** `extra_in_db` — the DB has a column the schema doesn't
      model. Non-breaking; Ecto just doesn't query it. Add to the
      schema only if you need to read/write that column.

    * **[OK]** schema in sync.

  ## Usage

      AUMENTA_MI_PENSION_DATABASE_URL='postgresql://...' mix amp.schema_drift

  Designed to run in CI on every PR — see `.github/workflows/schema-drift.yml`.

  ## Why not start the full app

  This task opens its own Postgrex connection from the URL env var
  instead of going through `Application.ensure_all_started/1`. Keeps
  CI runs fast and quiet (no background workers spinning up just to
  immediately exit).
  """

  use Mix.Task

  alias Ledgr.Domains.AumentaMiPension.BotOwnedSchemas

  @impl Mix.Task
  def run(_args) do
    # Compile so the schema modules are loaded (we need __schema__/1).
    Mix.Task.run("compile")

    url =
      System.get_env("AUMENTA_MI_PENSION_DATABASE_URL") ||
        Mix.raise("""
        AUMENTA_MI_PENSION_DATABASE_URL is not set.

        Set it in your shell or (in CI) as a GitHub Actions secret.
        Locally, your dev override in config/dev.secret.exs is fine.
        """)

    conn = open_connection!(url)

    results = Enum.map(BotOwnedSchemas.schemas(), &check_one(conn, &1))

    Enum.each(results, &print_report/1)
    print_summary(results)

    if Enum.any?(results, &(&1.missing_in_db != [])) do
      System.halt(1)
    end
  end

  defp open_connection!(url) do
    # Postgrex's connection pool needs its supervision tree up
    # (DBConnection.Watcher etc.) before start_link will work.
    {:ok, _} = Application.ensure_all_started(:postgrex)

    uri = URI.parse(url)
    [username, password] = String.split(uri.userinfo || ":", ":", parts: 2)

    {:ok, conn} =
      Postgrex.start_link(
        hostname: uri.host,
        port: uri.port || 5432,
        username: username,
        password: password,
        database: String.trim_leading(uri.path || "/", "/"),
        ssl: [
          verify: :verify_none,
          server_name_indication: to_charlist(uri.host || "")
        ]
      )

    conn
  end

  defp check_one(conn, schema_mod) do
    table = schema_mod.__schema__(:source)

    ecto_fields =
      schema_mod.__schema__(:fields)
      |> Enum.map(&Atom.to_string/1)
      |> MapSet.new()

    %Postgrex.Result{rows: rows} =
      Postgrex.query!(
        conn,
        "SELECT column_name FROM information_schema.columns WHERE table_name = $1",
        [table]
      )

    db_columns = rows |> List.flatten() |> MapSet.new()

    %{
      module: schema_mod,
      table: table,
      missing_in_db: ecto_fields |> MapSet.difference(db_columns) |> Enum.sort(),
      extra_in_db: db_columns |> MapSet.difference(ecto_fields) |> Enum.sort(),
      db_columns_count: MapSet.size(db_columns)
    }
  end

  defp print_report(%{db_columns_count: 0} = r) do
    # Table doesn't exist on the DB at all — really bad.
    IO.puts("[FAIL] #{inspect(r.module)} (#{r.table})")
    IO.puts("  Table does not exist on the live DB.")
  end

  defp print_report(%{missing_in_db: [_ | _]} = r) do
    IO.puts("[FAIL] #{inspect(r.module)} (#{r.table})")
    IO.puts("  Schema declares fields not in DB: #{inspect(r.missing_in_db)}")
    IO.puts("  → SELECT queries WILL crash. Remove these from the schema.")

    if r.extra_in_db != [] do
      IO.puts("  Also note — DB has columns we don't model: #{inspect(r.extra_in_db)}")
    end
  end

  defp print_report(%{extra_in_db: [_ | _]} = r) do
    IO.puts("[INFO] #{inspect(r.module)} (#{r.table})")
    IO.puts("  DB has columns not in our schema: #{inspect(r.extra_in_db)}")
    IO.puts("  Non-breaking. Add to schema if you want to query them.")
  end

  defp print_report(r) do
    IO.puts("[OK]   #{inspect(r.module)} (#{r.table})")
  end

  defp print_summary(results) do
    failed = Enum.count(results, &(&1.missing_in_db != [] or &1.db_columns_count == 0))
    info = Enum.count(results, &(&1.missing_in_db == [] and &1.extra_in_db != []))
    ok = length(results) - failed - info

    IO.puts("")
    IO.puts("Summary: #{ok} OK · #{info} INFO · #{failed} FAIL")

    if failed > 0 do
      IO.puts("Build will fail. Fix the [FAIL] schemas above.")
    end
  end
end
