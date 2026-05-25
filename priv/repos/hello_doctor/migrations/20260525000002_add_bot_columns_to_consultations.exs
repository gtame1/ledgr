defmodule Ledgr.Repos.HelloDoctor.Migrations.AddBotColumnsToConsultations do
  use Ecto.Migration

  # Bot-owned columns on `consultations` that the dashboard's rating /
  # cost / funnel metrics read. They already exist in prod (the bot
  # service migrations created them); this just syncs local dev DBs so
  # our queries don't fail in dev.
  #
  # IF NOT EXISTS makes this a no-op when the column is already there
  # (i.e. in any env where the bot's own migrations ran first).
  # Per CLAUDE.md the bot owns these columns — we don't set defaults,
  # nullability, or indexes, just ensure they exist.

  def up do
    execute("ALTER TABLE consultations ADD COLUMN IF NOT EXISTS tenant text")
    execute("ALTER TABLE consultations ADD COLUMN IF NOT EXISTS doctor_rating integer")

    execute(
      "ALTER TABLE consultations ADD COLUMN IF NOT EXISTS patient_platform_rating integer"
    )

    execute(
      "ALTER TABLE consultations ADD COLUMN IF NOT EXISTS doctor_platform_rating integer"
    )

    execute("ALTER TABLE consultations ADD COLUMN IF NOT EXISTS doctor_comment text")
    execute("ALTER TABLE consultations ADD COLUMN IF NOT EXISTS doctor_ping_count integer")

    execute(
      "ALTER TABLE consultations ADD COLUMN IF NOT EXISTS search_extended_count integer"
    )

    execute("ALTER TABLE consultations ADD COLUMN IF NOT EXISTS data_review_sent_at timestamp")
  end

  def down do
    # Don't drop — bot owns these columns.
    :ok
  end
end
