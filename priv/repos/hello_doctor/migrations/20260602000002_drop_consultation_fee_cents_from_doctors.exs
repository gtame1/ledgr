defmodule Ledgr.Repos.HelloDoctor.Migrations.DropConsultationFeeCentsFromDoctors do
  use Ecto.Migration

  @moduledoc """
  Drops the short-lived `consultation_fee_cents` column added in
  20260602000001 and falls back to the bot-owned `consultation_fee_mxn`
  column that was already on the doctors table in prod.

  The bot already writes/reads `consultation_fee_mxn` (integer, whole
  pesos, NOT NULL DEFAULT 0) for the "direct" consultation flow — we
  shouldn't have a parallel Ledgr-owned column.

  Local dev DBs were never touched by the bot's migration, so the
  `consultation_fee_mxn` column may not exist yet. `ADD COLUMN IF NOT
  EXISTS` mirrors the bot's schema without conflicting in prod.
  """

  def up do
    # Ensure the bot-owned column exists locally so Ecto can read/write
    # it. Prod already has it from the bot's own migrations; this is a
    # no-op there.
    execute(
      "ALTER TABLE doctors ADD COLUMN IF NOT EXISTS consultation_fee_mxn integer NOT NULL DEFAULT 0"
    )

    # Backfill anything we may have written to the now-doomed cents
    # column into the bot's mxn column. Guarded by IF EXISTS on
    # consultation_fee_cents in case the previous migration was
    # already rolled back.
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'doctors' AND column_name = 'consultation_fee_cents'
      ) THEN
        UPDATE doctors
        SET consultation_fee_mxn = (consultation_fee_cents / 100)
        WHERE consultation_fee_cents IS NOT NULL
          AND COALESCE(consultation_fee_mxn, 0) = 0;
      END IF;
    END $$;
    """)

    execute("ALTER TABLE doctors DROP COLUMN IF EXISTS consultation_fee_cents")
  end

  def down do
    # No clean reversal — re-creating consultation_fee_cents wouldn't
    # restore the values it once held. Inverse is a no-op.
    :ok
  end
end
