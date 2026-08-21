defmodule Ledgr.Repos.AumentaMiPension.Migrations.FreezeJournalEntries do
  use Ecto.Migration

  @moduledoc """
  Marks this domain's ledger as historical and stops anything writing to it.

  Aumenta Mi Pensión no longer posts journal entries — the two functions that
  did (`StripeSync.create_payment_journal_entry/1` and
  `StripeRefunds.create_refund_journal_entry/1`) are gone, and the accounting
  routes are unrouted. Eight entries remain, all `consultation_payment`, the
  last written 2026-05-14.

  The tables are deliberately NOT dropped: they hold real, if brief, historical
  bookkeeping, and dropping them is unrecoverable. Instead they are commented
  and guarded, so a future accidental rewiring fails loudly in staging rather
  than quietly resuming a ledger nobody reads.

  `accounts` is left writable — it is a static chart of accounts, and a trigger
  there would break seeding a fresh environment.
  """

  def up do
    execute """
    COMMENT ON TABLE journal_entries IS
      'FROZEN 2026-08-20 — historical only (8 entries, last 2026-05-14). Aumenta Mi Pensión no longer posts to the general ledger. A BEFORE INSERT trigger enforces this.'
    """

    execute """
    COMMENT ON TABLE journal_lines IS
      'FROZEN 2026-08-20 — historical only. See journal_entries.'
    """

    execute """
    CREATE OR REPLACE FUNCTION amp_ledger_is_frozen() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION
        'Aumenta Mi Pensión no longer posts to the general ledger (frozen 2026-08-20). Writing to % means something was rewired by accident.', TG_TABLE_NAME;
    END;
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER journal_entries_frozen
      BEFORE INSERT OR UPDATE ON journal_entries
      FOR EACH ROW EXECUTE FUNCTION amp_ledger_is_frozen()
    """

    execute """
    CREATE TRIGGER journal_lines_frozen
      BEFORE INSERT OR UPDATE ON journal_lines
      FOR EACH ROW EXECUTE FUNCTION amp_ledger_is_frozen()
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS journal_lines_frozen ON journal_lines"
    execute "DROP TRIGGER IF EXISTS journal_entries_frozen ON journal_entries"
    execute "DROP FUNCTION IF EXISTS amp_ledger_is_frozen()"
    execute "COMMENT ON TABLE journal_entries IS NULL"
    execute "COMMENT ON TABLE journal_lines IS NULL"
  end
end
