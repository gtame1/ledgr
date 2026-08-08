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
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.AumentaMiPension, :manual)

# The Escuela de Dinero tables are owned by the bot and have no Ledgr migration
# on purpose — one would create them in the bot's real database on deploy. Stand
# them up here instead so controller tests have something to query. Must run
# BEFORE the repo goes into :manual sandbox mode, or the DDL has no owner.
# See Ledgr.Test.EscuelaDeDineroBotSchema.
Ledgr.Test.EscuelaDeDineroBotSchema.create!()
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.EscuelaDeDinero, :manual)
