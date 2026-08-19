# Cap async concurrency so sandbox-owner connections across all repos
# stay under Postgres max_connections (default 100). Every async test owns
# one connection per repo in DataCase, so max_cases * repos must fit.
ExUnit.start(max_cases: 5)
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.MrMunchMe, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.VolumeStudio, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.LedgrHQ, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.CasaTame, :manual)
# The bot has added columns to HD's `conversations` that correctly have no
# Ledgr migration (writing one would alter the bot's real table on deploy).
# Add them here so the mirror in Conversations.Conversation is queryable.
# Must run BEFORE :manual sandbox mode, or the DDL has no owner.
Ledgr.Test.HelloDoctorBotSchema.create!()
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.HelloDoctor, :manual)
# AMP's conversations/customers/consultations are bot-owned with no Ledgr
# migration, so the test database had no such tables. Stand them up here.
Ledgr.Test.AumentaMiPensionBotSchema.create!()
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.AumentaMiPension, :manual)

# The Escuela de Dinero tables are owned by the bot and have no Ledgr migration
# on purpose — one would create them in the bot's real database on deploy. Stand
# them up here instead so controller tests have something to query. Must run
# BEFORE the repo goes into :manual sandbox mode, or the DDL has no owner.
# See Ledgr.Test.EscuelaDeDineroBotSchema.
Ledgr.Test.EscuelaDeDineroBotSchema.create!()
Ecto.Adapters.SQL.Sandbox.mode(Ledgr.Repos.EscuelaDeDinero, :manual)
