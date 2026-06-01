defmodule Ledgr.Repos.HelloDoctor.Migrations.SplitRetentionsIvaIsr do
  use Ecto.Migration

  # The previous `retentions_cents` column lumped both ISR and IVA
  # withholdings together. Split into two so the JE (and any future
  # reporting) can distinguish them.
  #
  # Existing rows are migrated as ISR-only — the safer default since ISR
  # honorarios retention is the common Mexican payroll case. If any row
  # actually represented IVA, fix it via the edit form after deploy.
  def up do
    alter table(:doctor_payouts) do
      add_if_not_exists :iva_retention_cents, :integer, default: 0, null: false
      add_if_not_exists :isr_retention_cents, :integer, default: 0, null: false
    end

    flush()

    # Backfill any pre-existing retentions into ISR before dropping.
    # IF EXISTS so the migration is idempotent on environments where the
    # bot tooling (or a prior version) already dropped the column.
    execute("""
    UPDATE doctor_payouts
       SET isr_retention_cents = retentions_cents
     WHERE retentions_cents IS NOT NULL AND retentions_cents > 0
    """)

    execute("ALTER TABLE doctor_payouts DROP COLUMN IF EXISTS retentions_cents")
  end

  def down do
    alter table(:doctor_payouts) do
      add_if_not_exists :retentions_cents, :integer, default: 0, null: false
    end

    flush()

    # Roll the two back into one sum.
    execute("""
    UPDATE doctor_payouts
       SET retentions_cents =
           COALESCE(iva_retention_cents, 0) + COALESCE(isr_retention_cents, 0)
    """)

    alter table(:doctor_payouts) do
      remove_if_exists :iva_retention_cents
      remove_if_exists :isr_retention_cents
    end
  end
end
