defmodule Ledgr.Repo.Migrations.UpdateJournalEntryEntryTypeCheck do
  use Ecto.Migration

  def change do
    # First drop the old constraint (the one that doesn't include "order_delivered")
    execute("""
    ALTER TABLE journal_entries
    DROP CONSTRAINT IF EXISTS entry_type_check;
    """)
  end
end
