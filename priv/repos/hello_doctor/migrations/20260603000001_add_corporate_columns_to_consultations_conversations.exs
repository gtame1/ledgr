defmodule Ledgr.Repos.HelloDoctor.Migrations.AddCorporateColumnsToConsultationsConversations do
  use Ecto.Migration

  @moduledoc """
  Mirror of the bot's inline migration from ADR-046 (corporate accounts /
  employer-paid consultations). Bot-owned columns; we add them with
  `IF NOT EXISTS` so the migration is idempotent and orderings between
  the bot's deploy and ours don't conflict.

  Adds two columns to both `conversations` and `consultations`:
    * `payment_source VARCHAR NOT NULL DEFAULT 'stripe'` — `stripe`,
      `corporate`, or `test`. Drives doctor-payable gating in our reports:
      we pay the doctor for `('stripe','corporate')`; `'test'` rows are
      excluded.
    * `corporate_account_id VARCHAR` — nullable FK-by-convention to the
      bot-owned `corporate_accounts.id`. We don't add the FK constraint
      here (the bot may not have created `corporate_accounts` yet on
      local dev DBs, and our prod deploy may race the bot's). It's
      metadata-only correctness; not enforced in app logic.

  Per CLAUDE.md the bot owns these columns. We're not the source of truth
  for the DDL — this just keeps local dev + reports honest.
  """

  def up do
    execute(
      "ALTER TABLE conversations ADD COLUMN IF NOT EXISTS payment_source VARCHAR NOT NULL DEFAULT 'stripe'"
    )

    execute("ALTER TABLE conversations ADD COLUMN IF NOT EXISTS corporate_account_id VARCHAR")

    execute(
      "ALTER TABLE consultations ADD COLUMN IF NOT EXISTS payment_source VARCHAR NOT NULL DEFAULT 'stripe'"
    )

    execute("ALTER TABLE consultations ADD COLUMN IF NOT EXISTS corporate_account_id VARCHAR")

    execute(
      "CREATE INDEX IF NOT EXISTS ix_conversations_corporate_account_id ON conversations (corporate_account_id)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS ix_consultations_corporate_account_id ON consultations (corporate_account_id)"
    )
  end

  def down do
    # Bot owns these columns — don't drop on rollback.
    :ok
  end
end
