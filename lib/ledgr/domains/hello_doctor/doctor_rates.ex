defmodule Ledgr.Domains.HelloDoctor.DoctorRates do
  @moduledoc """
  What a doctor earns for a consultation.

  A pricing rule, not bookkeeping. Extracted from `ConsultationAccounting`,
  which mixed this with journal-entry posting — the posting is gone, this is
  not: thirteen call sites across the dashboard, lifecycle and acquisition
  metrics, the funnel exports, payouts and refunds all need it.

  The rule: a doctor's own DIRECT patients (conversation tenant `"direct"`)
  pay that doctor's negotiated `consultation_fee_mxn`; HD-sourced MVP — and
  anything not `"direct"`, or a direct consult with no configured fee — pays
  the flat share. Mirrored in `MonthlyReport`.
  """

  import Ecto.Query, warn: false

  alias Ledgr.Repo

  # Flat amount paid to the doctor for every paid consultation, in MXN.
  # Single source of truth.
  @doctor_share_mxn 100.0

  @doc "Flat doctor share per paid consultation, in MXN pesos."
  def doctor_share_mxn, do: @doctor_share_mxn

  @doc "Flat doctor share per paid consultation, in centavos."
  def doctor_share_cents, do: round(@doctor_share_mxn * 100)

  @doc """
  Tenant-aware doctor share in centavos for a specific consultation (loads its
  conversation tenant + doctor fee). Per-consultation counterpart of
  `doctor_share_cents/0`; use it wherever you must back out the exact amount
  `record_payment/2` posted to Doctor Payable — e.g. a refund reversal — so a
  $200 direct consult reverses $200, not the flat $100.
  """
  def doctor_share_cents(consultation), do: tenant_aware_doctor_cents(consultation)

  @doc """
  Tenant-aware doctor share, in MXN pesos. A doctor's own DIRECT patients
  (conversation tenant `"direct"`) pay that doctor's negotiated rate
  (`consultation_fee_mxn`); HD-sourced MVP — and anything not `"direct"`,
  or a direct consult with no configured fee — pays the flat share. Mirrors
  the rule in `MonthlyReport`; single source of truth for "what the doctor
  earns per consultation".
  """
  def doctor_share_mxn(tenant, fee) do
    if tenant == "direct" and is_number(fee) and fee > 0, do: fee * 1.0, else: @doctor_share_mxn
  end

  # Doctor share in centavos for a specific consultation, tenant-aware. Loads
  # the conversation tenant + doctor's negotiated fee and applies the same rule
  # as `doctor_share_mxn/2`. Falls back to the flat share when either is absent.
  defp tenant_aware_doctor_cents(consultation) do
    consultation = Ledgr.Repo.preload(consultation, [:conversation, :doctor])
    tenant = consultation.conversation && consultation.conversation.tenant
    fee = consultation.doctor && consultation.doctor.consultation_fee_mxn
    round(doctor_share_mxn(tenant, fee) * 100)
  end

  @doc """
  SQL-expression form of `doctor_share_mxn/2` for raw-SQL contexts. Pass the
  in-scope SQL expressions for the conversation tenant and the doctor's
  `consultation_fee_mxn`; returns pesos as float8.
  """
  def doctor_share_sql(tenant_expr, fee_expr) do
    "(CASE WHEN #{tenant_expr} = 'direct' AND COALESCE(#{fee_expr}, 0) > 0 " <>
      "THEN (#{fee_expr})::float8 ELSE #{@doctor_share_mxn} END)"
  end

  @doc """
  Doctor share in centavos for a consultation id.

  Same rule as `doctor_share_cents/1`, but reads the tenant and the doctor's
  fee with one raw query instead of preloading the bot-owned `Conversation`
  schema. Was `ConsultationAccounting.corporate_doctor_cents/1`.
  """
  def doctor_share_cents_for_consultation_id(consultation_id) do
    sql = """
    SELECT conv.tenant, d.consultation_fee_mxn
    FROM consultations c
    LEFT JOIN conversations conv ON conv.id = c.conversation_id
    LEFT JOIN doctors d ON d.id = c.doctor_id
    WHERE c.id = $1
    """

    {tenant, fee} =
      case Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [consultation_id]) do
        %{rows: [[tenant, fee]]} -> {tenant, to_number(fee)}
        _ -> {nil, nil}
      end

    round(doctor_share_mxn(tenant, fee) * 100)
  end

  defp to_number(nil), do: nil
  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_number(n) when is_number(n), do: n
end
