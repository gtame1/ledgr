defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateCorporateSettlements do
  use Ecto.Migration

  @moduledoc """
  Gives corporate invoice settlements a table of their own.

  Until now the settlement *was* a journal entry: `settlement_for/2` looked one
  up by reference, `settled?/2` derived from its existence, and the amount came
  from summing its lines. That worked while Hello Doctor posted to the general
  ledger. It no longer will, so the "has this employer paid?" state needs
  somewhere real to live.

  Backfills from the entries written so far, keyed on the same
  `"Corporate settlement — <slug> <month>"` reference the module generates, so
  nothing is lost on environments that do have rows. (Production has none at
  the time of writing — the feature has been barely piloted — but the backfill
  is correct either way and must run before anything stops writing entries.)
  """

  def up do
    create table(:corporate_settlements) do
      add :account_slug, :string, null: false
      add :month, :string, null: false
      add :amount_cents, :integer, null: false
      add :deposit_code, :string, null: false, default: "1010"
      add :settled_on, :date, null: false
      add :account_name, :string
      # Historical pointer to the journal entry this used to be. Null for
      # anything recorded after the GL removal.
      add :journal_entry_id, :integer

      timestamps(type: :utc_datetime)
    end

    # One settlement per (account, month) — the idempotency guarantee
    # record_settlement/3 used to get from the entry reference being unique.
    create unique_index(:corporate_settlements, [:account_slug, :month])

    flush()

    execute("""
    INSERT INTO corporate_settlements
      (account_slug, month, amount_cents, deposit_code, settled_on,
       account_name, journal_entry_id, inserted_at, updated_at)
    SELECT
      split_part(substring(je.reference from 'Corporate settlement — (.*)$'), ' ', 1) AS account_slug,
      split_part(substring(je.reference from 'Corporate settlement — (.*)$'), ' ', 2) AS month,
      COALESCE((SELECT SUM(jl.debit_cents) FROM journal_lines jl
                 WHERE jl.journal_entry_id = je.id), 0)::int                          AS amount_cents,
      COALESCE((SELECT a.code FROM journal_lines jl
                  JOIN accounts a ON a.id = jl.account_id
                 WHERE jl.journal_entry_id = je.id AND jl.debit_cents > 0
                 LIMIT 1), '1010')                                                    AS deposit_code,
      je.date                                                                         AS settled_on,
      je.payee                                                                        AS account_name,
      je.id                                                                           AS journal_entry_id,
      NOW() AT TIME ZONE 'UTC',
      NOW() AT TIME ZONE 'UTC'
    FROM journal_entries je
    WHERE je.reference LIKE 'Corporate settlement — %'
    ON CONFLICT (account_slug, month) DO NOTHING
    """)
  end

  def down do
    drop table(:corporate_settlements)
  end
end
