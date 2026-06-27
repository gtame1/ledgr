defmodule Ledgr.Repos.HelloDoctor.Migrations.AddAmountToPayoutConsultations do
  use Ecto.Migration

  @moduledoc """
  Records how much of a payout was paid toward each consultation it covers.

  `doctor_payouts.amount_cents` is the batch total; until now the join
  carried no per-consultation split. Allocation rule (mirrors
  `DoctorPayouts`): assume each consultation was paid its calculated share
  ($100); if those sum to the payout's actual `amount_cents`, use them
  as-is; otherwise fall back to an even split of the actual amount (remainder
  to the lowest-id rows) so the parts always reconcile to the total.
  """

  @share_cents 10_000

  def up do
    alter table(:doctor_payout_consultations) do
      add :amount_cents, :integer
    end

    flush()

    # 1. Exact-match payouts: every consultation gets its $100 share.
    execute """
    WITH counts AS (
      SELECT doctor_payout_id, COUNT(*) AS n
      FROM doctor_payout_consultations
      GROUP BY doctor_payout_id
    )
    UPDATE doctor_payout_consultations j
    SET amount_cents = #{@share_cents}
    FROM counts c
    JOIN doctor_payouts p ON p.id = c.doctor_payout_id
    WHERE j.doctor_payout_id = c.doctor_payout_id
      AND c.n * #{@share_cents} = p.amount_cents
    """

    # 2. Everything else: even split of the actual amount_cents, with the
    #    remainder handed to the lowest-id rows so the parts sum to the total.
    execute """
    WITH ranked AS (
      SELECT
        j.id,
        p.amount_cents AS total,
        COUNT(*) OVER (PARTITION BY j.doctor_payout_id) AS n,
        ROW_NUMBER() OVER (PARTITION BY j.doctor_payout_id ORDER BY j.id) - 1 AS idx
      FROM doctor_payout_consultations j
      JOIN doctor_payouts p ON p.id = j.doctor_payout_id
      WHERE j.amount_cents IS NULL
    )
    UPDATE doctor_payout_consultations j
    SET amount_cents = (r.total / r.n) + CASE WHEN r.idx < (r.total % r.n) THEN 1 ELSE 0 END
    FROM ranked r
    WHERE r.id = j.id
    """
  end

  def down do
    alter table(:doctor_payout_consultations) do
      remove :amount_cents
    end
  end
end
