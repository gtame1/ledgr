defmodule Ledgr.SchemaDrift do
  @moduledoc """
  Compares Ecto schemas that mirror an **externally-owned** table against
  `information_schema.columns` on the live database, and reports drift.

  Several Ledgr domains read from a database whose migrations live in another
  repo (a Python bot, typically). When that service drops or renames a column we
  mirror, nothing fails until a page 500s in production — the class of bug that
  took down AMP on 2026-05-23. This runs in CI instead.

  ## Categories

    * **[FAIL]** `missing_in_db` — the schema declares a field the DB doesn't
      have. Every `SELECT` against that table will crash with
      `undefined_column`. Remove the field from the schema before shipping.

    * **[INFO]** `extra_in_db` — the DB has a column the schema doesn't model.
      Non-breaking; Ecto just doesn't query it. Add it only if you need it.

    * **[OK]** in sync.

  ## Why it opens its own connection

  It connects straight from the URL rather than booting the app, so CI runs stay
  fast and quiet — no background workers spinning up just to exit.

  Driven by the thin `mix amp.schema_drift` / `mix edd.schema_drift` tasks.
  """

  @doc """
  Runs the drift check for `schemas` against the database at `url`.

  Prints a per-schema report and a summary, then halts non-zero if any schema
  declares a field the database doesn't have.
  """
  def run!(url, schemas) do
    conn = open_connection!(url)

    results = Enum.map(schemas, &check_one(conn, &1))

    Enum.each(results, &print_report/1)
    print_summary(results)

    if Enum.any?(results, &(&1.missing_in_db != [] or &1.db_columns_count == 0)) do
      System.halt(1)
    end
  end

  @doc """
  Fetches `env_var` or raises a Mix error naming it.
  """
  def url_from_env!(env_var) do
    System.get_env(env_var) ||
      Mix.raise("""
      #{env_var} is not set.

      Set it in your shell or (in CI) as a GitHub Actions secret.
      Locally, your dev override in config/dev.secret.exs is fine.
      """)
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
