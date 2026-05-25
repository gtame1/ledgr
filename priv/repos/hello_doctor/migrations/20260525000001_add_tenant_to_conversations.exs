defmodule Ledgr.Repos.HelloDoctor.Migrations.AddTenantToConversations do
  use Ecto.Migration

  # The bot writes a `tenant` column on `conversations` (values like
  # 'direct' / 'mvp') and our dashboard's funnel-by-segment query reads
  # it. The column already exists in prod (bot service migrations have
  # created it). This adds it conditionally so local dev DBs that pre-date
  # it match prod — using IF NOT EXISTS so it's a no-op in prod and any
  # env where the bot's own migrations already ran.
  #
  # Per CLAUDE.md this table is bot-owned, but adding a column that
  # already exists upstream is purely a defensive sync, not a data-model
  # change. No constraints / defaults are set so the bot retains full
  # control of how the column behaves.

  def up do
    execute("ALTER TABLE conversations ADD COLUMN IF NOT EXISTS tenant text")
  end

  def down do
    # Don't drop — the bot owns this column. Leaving it intact is safe
    # whether we rolled back or the bot also writes here.
    :ok
  end
end
