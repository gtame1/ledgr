defmodule Ledgr.Domains.EscuelaDeDinero.BotOwnedSchemas do
  @moduledoc """
  Canonical registry of Ecto schemas mirroring **bot-owned** tables on the
  Escuela de Dinero database.

  `escuela-de-dinero-bot` (FastAPI + SQLModel, Alembic) is the source of truth
  for every table here. Ledgr owns exactly one table in this database — `users`,
  for login — and never migrates anything else. See CLAUDE.md
  "Escuela de Dinero — schema ownership".

  Consumed by `mix edd.schema_drift`, which diffs each schema's declared fields
  against `information_schema.columns` on the live DB and fails the build when a
  column we read has been dropped or renamed.

  ## Deliberately not mirrored

  These bot tables exist in the schema but have **no production writer** today,
  so a page over them would be structurally empty:

    * `checkins` — the sweep queries `movimientos` directly; only a test inserts
      a Checkin row.
    * `alert_events` — `alerts.py` pages over WhatsApp and counts from
      `policing_events`; nothing inserts here.
    * `experiment_assignments` / `experiment_definitions` / `experiment_results`
      — experiments are disabled (`experiments_enabled = False`).
    * `webhook_dedup` — pure idempotency ledger, nothing to report on.

  Add them here (and build the pages) once the bot starts writing them.
  """

  alias Ledgr.Domains.EscuelaDeDinero, as: EDD

  @schemas [
    EDD.People.Person,
    EDD.Conversations.Conversation,
    EDD.Messages.Message,
    EDD.Diagnosticos.Diagnostico,
    EDD.Movimientos.Movimiento,
    EDD.PolicingEvents.PolicingEvent,
    EDD.OutboundMessages.OutboundMessage,
    EDD.KuboReferrals.KuboReferral
  ]

  @doc "All bot-owned Ecto schema modules we mirror."
  def schemas, do: @schemas
end
