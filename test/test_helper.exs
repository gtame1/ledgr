# Cap async concurrency so sandbox-owner connections across all repos
# stay under Postgres max_connections (default 100). Every async test owns
# one connection per repo in DataCase, so max_cases * repos must fit.
ExUnit.start(max_cases: 5)
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.MrMunchMe, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.Viaxe, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.VolumeStudio, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.LedgrHQ, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.CasaTame, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.HelloDoctor, :manual)
