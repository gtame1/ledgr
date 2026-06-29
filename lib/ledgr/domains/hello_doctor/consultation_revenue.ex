defmodule Ledgr.Domains.HelloDoctor.ConsultationRevenue do
  @moduledoc """
  Per-consultation revenue breakdown for the consultation & conversation
  reports: gross paid, doctor share, Stripe fee, and HD net (our margin).

  Same money model as `DoctorPayouts.list_consultations_with_payouts/3`:

    * **gross** — what the patient paid: `stripe_payments.amount` when the
      charge has synced, else `consultations.payment_amount` (both in MXN
      pesos).
    * **doctor_share** — the frozen $100 from `consultation_payouts`
      (authoritative), falling back to the flat
      `ConsultationAccounting.doctor_share_mxn/0` for any billed
      consultation without a snapshot row yet.
    * **stripe_fee** / **refunded** — from `stripe_payments`.
    * **hd_net** — `gross − stripe_fee − doctor_share − refunded`.

  Only billed, non-test consultations (`payment_status` in
  paid/confirmed/refunded) carry revenue; everything else is absent from
  the map (callers render "—").

  `doctor_share` here is the gross earned share — it is NOT reduced by the
  pay/don't-pay decision (that's a payout-processing concern, not revenue).
  """

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting
  alias Ledgr.Domains.HelloDoctor.TestAccounts

  @doc "Revenue keyed by consultation id, for the given consultation ids."
  def for_consultations(ids) when is_list(ids) do
    ids |> rows("c.id") |> Map.new(&{&1.consultation_id, &1})
  end

  def for_consultations(_), do: %{}

  @doc """
  Revenue keyed by conversation id, summed across each conversation's
  billed consultations (a conversation can have more than one).
  """
  def for_conversations(ids) when is_list(ids) do
    ids
    |> rows("c.conversation_id")
    |> Enum.group_by(& &1.conversation_id)
    |> Map.new(fn {conv_id, rs} -> {conv_id, aggregate(rs)} end)
  end

  def for_conversations(_), do: %{}

  defp rows([], _filter_col), do: []

  defp rows(ids, filter_col) when is_list(ids) do
    # Fallback share (for any consult not yet frozen) is tenant-aware, same
    # rule as the frozen value: direct → the doctor's fee, else flat.
    share_fallback = ConsultationAccounting.doctor_share_sql("conv.tenant", "d.consultation_fee_mxn")

    sql = """
    SELECT
      c.id,
      c.conversation_id,
      COALESCE(spx.amount, c.payment_amount)        AS gross,
      COALESCE(spx.stripe_fee, 0)                   AS stripe_fee,
      COALESCE(spx.amount_refunded, 0)              AS refunded,
      COALESCE(cp.doctor_share_cents / 100.0, #{share_fallback}) AS doctor_share,
      COALESCE(c.payment_source, 'stripe')          AS payment_source,
      (spx.amount IS NOT NULL)                      AS stripe_synced
    FROM consultations c
    LEFT JOIN conversations conv ON conv.id = c.conversation_id
    LEFT JOIN doctors d ON d.id = c.doctor_id
    LEFT JOIN LATERAL (
      SELECT sp.amount, sp.stripe_fee, sp.amount_refunded
      FROM stripe_payments sp
      WHERE sp.consultation_id = c.id
         OR (sp.consultation_id IS NULL
             AND c.stripe_payment_intent_id IS NOT NULL
             AND sp.stripe_payment_intent_id = c.stripe_payment_intent_id)
      ORDER BY sp.id
      LIMIT 1
    ) spx ON TRUE
    LEFT JOIN consultation_payouts cp ON cp.consultation_id = c.id
    WHERE #{filter_col} = ANY($1)
      AND c.payment_status IN ('paid', 'confirmed', 'refunded')
      AND COALESCE(c.payment_source, 'stripe') <> 'test'
      AND #{TestAccounts.not_test_patient_sql("c.patient_id")}
    """

    %{rows: rows} = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [ids])
    Enum.map(rows, &decode/1)
  end

  defp decode([id, conv_id, gross, fee, refunded, share, source, synced]) do
    gross = to_f(gross)
    fee = to_f(fee)
    refunded = to_f(refunded)
    share = to_f(share)

    %{
      consultation_id: id,
      conversation_id: conv_id,
      gross: r2(gross),
      stripe_fee: r2(fee),
      refunded: r2(refunded),
      doctor_share: r2(share),
      hd_net: r2(gross - fee - share - refunded),
      payment_source: source,
      stripe_synced?: synced
    }
  end

  defp aggregate(rows) do
    sum = fn key -> rows |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum() end

    %{
      gross: r2(sum.(:gross)),
      stripe_fee: r2(sum.(:stripe_fee)),
      refunded: r2(sum.(:refunded)),
      doctor_share: r2(sum.(:doctor_share)),
      hd_net: r2(sum.(:hd_net)),
      count: length(rows)
    }
  end

  defp to_f(nil), do: 0.0
  defp to_f(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_f(n) when is_integer(n), do: n * 1.0
  defp to_f(n) when is_float(n), do: n

  defp r2(f), do: Float.round(f, 2)
end
