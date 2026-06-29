defmodule Ledgr.Repos.HelloDoctor.Migrations.CorrectDirectDoctorShares do
  use Ecto.Migration

  @moduledoc """
  One-time correction: `consultation_payouts` was frozen with a flat $100
  doctor share for every consultation, but DIRECT consultations earn the
  doctor's own `consultation_fee_mxn`. Re-set the frozen share to the
  tenant-aware value (mirrors ConsultationAccounting / MonthlyReport) for any
  row that's wrong. Flat-share rows are untouched.
  """

  @share """
  (CASE WHEN conv.tenant = 'direct' AND COALESCE(d.consultation_fee_mxn, 0) > 0
        THEN d.consultation_fee_mxn::float8 ELSE 100.0 END)
  """

  def up do
    execute """
    UPDATE consultation_payouts cp
    SET doctor_share_cents = ROUND(#{@share} * 100)::int,
        updated_at = NOW()
    FROM consultations c
    LEFT JOIN conversations conv ON conv.id = c.conversation_id
    LEFT JOIN doctors d ON d.id = c.doctor_id
    WHERE c.id = cp.consultation_id
      AND cp.doctor_share_cents <> ROUND(#{@share} * 100)::int
    """
  end

  # Data correction — nothing to roll back to (the prior values were wrong).
  def down, do: :ok
end
