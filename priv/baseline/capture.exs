# Phase 0.0 / Phase 11 baseline capture.
#
# Records what "working" looks like so the end-of-cleanup check is a diff and
# not a judgement call. Run once on the pre-cleanup tree, then again after, and
# compare the two directories.
#
#   MIX_ENV=dev mix run priv/baseline/capture.exs tmp/baseline
#   ... do the cleanup ...
#   MIX_ENV=dev mix run priv/baseline/capture.exs tmp/after
#   diff -ru tmp/baseline tmp/after
#
# Captures, per surviving domain:
#   * every path in menu_items/0 — HTTP status and a SHA of the response body
#   * row counts for every table in that domain's repo
#
# The body SHA rather than the body itself: dashboards embed dates and totals
# that move on their own, so a raw diff is noise. A changed SHA is a prompt to
# look, and `bodies/` keeps the HTML when you need to.
#
# Pages are driven through the endpoint with a real session, exactly as
# Phase 11 describes, so this exercises routing, auth and rendering together.

require Logger

# Dev logs every query; at ~120 tables plus 54 pages that dominates the runtime.
Logger.configure(level: :warning)

out_dir = System.argv() |> List.first() || "tmp/baseline"
File.mkdir_p!(Path.join(out_dir, "bodies"))

domains = [
  {Ledgr.Domains.MrMunchMe, Ledgr.Repos.MrMunchMe},
  {Ledgr.Domains.HelloDoctor, Ledgr.Repos.HelloDoctor},
  {Ledgr.Domains.AumentaMiPension, Ledgr.Repos.AumentaMiPension},
  {Ledgr.Domains.EscuelaDeDinero, Ledgr.Repos.EscuelaDeDinero}
]

started = Ledgr.Repo.all_repos()

# ── Row counts ────────────────────────────────────────────────────────────
counts =
  for {domain, repo} <- domains, repo in started do
    Ledgr.Repo.put_active_repo(repo)

    tables =
      case Ecto.Adapters.SQL.query(
             repo,
             "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY 1",
             []
           ) do
        {:ok, %{rows: rows}} -> Enum.map(rows, &hd/1)
        {:error, _} -> []
      end

    for t <- tables do
      sql = ~s|SELECT count(*) FROM "| <> t <> ~s|"|

      n =
        case Ecto.Adapters.SQL.query(repo, sql, []) do
          {:ok, %{rows: [[c]]}} -> c
          {:error, _} -> "ERR"
        end

      "#{domain.slug()}\t#{t}\t#{n}"
    end
  end
  |> List.flatten()

File.write!(Path.join(out_dir, "counts.tsv"), Enum.join(counts, "\n") <> "\n")
IO.puts("counts.tsv: #{length(counts)} tables")

# ── Page sweep ────────────────────────────────────────────────────────────
# Derived from menu_items/0 rather than hardcoded, so it stays honest as the
# menus change — and because menu_items/0 is the SOLE nav source for every
# domain implementing nav_icons/0, a page missing from it is unreachable.
results =
  for {domain, repo} <- domains, repo in started do
    Ledgr.Repo.put_active_repo(repo)

    # Idempotent: the script is meant to run twice (before and after), and the
    # dev database persists between runs.
    email = "baseline-#{domain.slug()}@local.test"

    user =
      case Ledgr.Core.Accounts.get_user_by_email(email) do
        nil ->
          {:ok, u} = Ledgr.Core.Accounts.create_user(%{email: email, password: "password123!"})
          u

        existing ->
          existing
      end

    conn_for = fn ->
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{"user_id:#{domain.slug()}" => user.id})
    end

    paths =
      domain.menu_items()
      |> Enum.flat_map(fn
        %{items: items} -> items
        item -> [item]
      end)
      |> Enum.map(& &1.path)
      |> Enum.uniq()

    for path <- paths do
      {status, sha} =
        try do
          conn = Phoenix.ConnTest.dispatch(conn_for.(), LedgrWeb.Endpoint, :get, path)
          body = conn.resp_body || ""

          File.write!(
            Path.join([out_dir, "bodies", String.replace(path, "/", "_") <> ".html"]),
            body
          )

          {conn.status, :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)}
        rescue
          e ->
            reason =
              e
              |> Exception.message()
              |> String.split("\n")
              |> hd()
              |> String.slice(0, 160)

            {"RAISED", reason}
        end

      IO.puts("#{status}\t#{path}")
      "#{status}\t#{path}\t#{sha}"
    end
  end
  |> List.flatten()

File.write!(Path.join(out_dir, "pages.tsv"), Enum.join(results, "\n") <> "\n")
IO.puts("\npages.tsv: #{length(results)} pages")

bad = Enum.reject(results, &String.starts_with?(&1, "200\t"))
if bad != [], do: IO.puts("\nNOT 200 (#{length(bad)}):\n" <> Enum.join(bad, "\n"))
