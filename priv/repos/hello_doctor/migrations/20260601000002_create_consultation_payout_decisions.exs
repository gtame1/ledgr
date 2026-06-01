defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateConsultationPayoutDecisions do
  use Ecto.Migration

  @moduledoc """
  Replaces the short-lived `stripe_payments.pay_doctor` column (added
  in 20260601000001) with a Ledgr-owned sidecar table keyed by
  `consultation_id`.

  Why: the previous design couldn't represent "still pay doctor" for
  consultations without a `stripe_payments` row (e.g. 100% discount
  consultations the bot writes as `cs_no_payment_*`). Keying off the
  consultation directly makes the override apply uniformly.

  Steps:
    1. Create the table + unique index on consultation_id
    2. Backfill from existing `stripe_payments` rows where pay_doctor=false
       (preserving the prior decision for refunded consultations)
    3. Drop the now-unused column from stripe_payments
  """

  def change do
    create table(:consultation_payout_decisions) do
      # String to match the bot-owned `consultations.id` column type.
      add :consultation_id, :string, null: false
      # The single source of truth for "do we owe this doctor for this
      # consultation?" Defaults to true; flipped to false on refund
      # unless the operator opted in to the override.
      add :pay_doctor, :boolean, default: true, null: false
      # Optional free-text reason — useful for audit later.
      add :reason, :text
      # Operator email (or "system" for auto-set values).
      add :decided_by, :string

      timestamps()
    end

    create unique_index(:consultation_payout_decisions, [:consultation_id])

    # Backfill from the soon-to-be-dropped column. We only need to
    # preserve the *negative* state — `pay_doctor=false` rows. The
    # absence of a decision row is interpreted as "pay the doctor"
    # everywhere we read it, which matches the column default.
    execute(
      """
      INSERT INTO consultation_payout_decisions
        (consultation_id, pay_doctor, reason, decided_by, inserted_at, updated_at)
      SELECT
        sp.consultation_id,
        FALSE,
        'backfilled from stripe_payments.pay_doctor',
        'system',
        NOW(),
        NOW()
      FROM stripe_payments sp
      WHERE sp.consultation_id IS NOT NULL
        AND sp.pay_doctor = FALSE
      ON CONFLICT (consultation_id) DO NOTHING
      """,
      "DELETE FROM consultation_payout_decisions WHERE decided_by = 'system' AND reason LIKE 'backfilled%'"
    )

    alter table(:stripe_payments) do
      remove :pay_doctor, :boolean, default: true, null: false
    end
  end
end
