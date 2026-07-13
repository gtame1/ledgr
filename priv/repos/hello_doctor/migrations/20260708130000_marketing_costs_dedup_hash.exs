defmodule Ledgr.Repos.HelloDoctor.Migrations.MarketingCostsDedupHash do
  use Ecto.Migration

  @moduledoc """
  Concurrency-safe idempotency for marketing cost imports.

  A slow bulk import once looked hung and got submitted several times; with no
  unique constraint, the concurrent requests each inserted the whole file and
  triple-counted spend. This adds a DB-generated `dedup_hash` over the full
  charge identity (platform + date + source + currency + description + amount)
  and a UNIQUE index on it, so `insert_all(..., on_conflict: :nothing)` makes a
  re-upload a no-op regardless of timing.

  Assumes existing duplicate rows have already been removed (they were).

  NOTE: a generated column's expression must be IMMUTABLE, so `date::text` (which
  depends on the DateStyle session setting) is rejected. We encode the date as an
  immutable integer day-count (`date - DATE '2000-01-01'`) instead. Idempotent
  (IF NOT EXISTS / create_if_not_exists) because prod already had this applied
  out-of-band while recovering from the deploy that shipped the schema field
  ahead of this migration.
  """

  def up do
    execute("""
    ALTER TABLE marketing_costs
      ADD COLUMN IF NOT EXISTS dedup_hash text GENERATED ALWAYS AS (
        md5(
          platform || '|' || (date - DATE '2000-01-01')::text || '|' || source ||
          '|' || currency || '|' || coalesce(description, '') || '|' || amount::text
        )
      ) STORED
    """)

    create_if_not_exists(unique_index(:marketing_costs, [:dedup_hash]))
  end

  def down do
    drop_if_exists(index(:marketing_costs, [:dedup_hash]))
    execute("ALTER TABLE marketing_costs DROP COLUMN IF EXISTS dedup_hash")
  end
end
