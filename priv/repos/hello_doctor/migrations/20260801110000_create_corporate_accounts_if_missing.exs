defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateCorporateAccountsIfMissing do
  use Ecto.Migration

  @moduledoc """
  Bootstraps the bot-owned `corporate_accounts` table on databases where the
  bot hasn't created it — same spirit as `20260603000001`, which mirrors the
  bot's corporate columns with `IF NOT EXISTS`.

  Why this is needed: as of `20260801120000` two Ledgr-owned readers join the
  table — `analytics.fct_consultation` (in the view definition, so the
  migration itself fails without it) and
  `CorporateSettlements.booked_ar_cents/2`. On prod the bot created the table
  long ago (ADR-046) so both are no-ops there, but a freshly created dev/test
  DB has only Ledgr's migrations, and `mix ecto.migrate` for
  `Ledgr.Repos.HelloDoctor` errors out with
  `relation "corporate_accounts" does not exist`.

  Shape mirrors prod (verified 2026-08-03): `consultation_rate_mxn` is a
  nullable integer in whole pesos. The bot remains the source of truth for the
  DDL — this only fills the gap so local dev/test can migrate and the corporate
  code paths can be exercised. `IF NOT EXISTS` means the bot's own table always
  wins where it already exists.
  """

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS corporate_accounts (
      id                    VARCHAR PRIMARY KEY,
      slug                  VARCHAR NOT NULL,
      name                  VARCHAR NOT NULL,
      status                VARCHAR NOT NULL DEFAULT 'active',
      consultation_rate_mxn INTEGER,
      created_at            TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'UTC')
    )
    """)

    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS ix_corporate_accounts_slug ON corporate_accounts (slug)"
    )
  end

  def down do
    # Bot owns this table — don't drop on rollback.
    :ok
  end
end
