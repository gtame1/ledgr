defmodule Ledgr.Domains.AumentaMiPension.DashboardMetrics do
  @moduledoc """
  Aggregate operational metrics for the Aumenta Mi Pensión dashboard.

  Covers the funnel from WhatsApp greeting → qualified → simulation sent →
  consultation booked → paid, plus operational metrics on consultations and
  revenue (once Stripe is configured).
  """

  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.Consultations.Consultation
  alias Ledgr.Domains.AumentaMiPension.Conversations.Conversation
  alias Ledgr.Domains.AumentaMiPension.Agents.Agent
  alias Ledgr.Domains.AumentaMiPension.PensionCases.PensionCase
  alias Ledgr.Domains.AumentaMiPension.StripePayments.StripePayment

  @commission_rate 0.15

  def all(start_date, end_date) do
    %{
      funnel: funnel_metrics(start_date, end_date),
      operations: operations_metrics(start_date, end_date),
      revenue: revenue_metrics(start_date, end_date),
      pension_cases: pension_case_metrics(start_date, end_date),
      daily_series: daily_series(start_date, end_date),
      db_size: db_size(),
      total_agents: count_agents(),
      active_agents: count_active_agents()
    }
  end

  def funnel_metrics(start_date, end_date) do
    conversations_count =
      Conversation
      |> where_date_range(:created_at, start_date, end_date)
      |> Repo.aggregate(:count)

    qualified_count =
      Conversation
      |> where_date_range(:created_at, start_date, end_date)
      |> where([c], c.qualifies == true)
      |> Repo.aggregate(:count)

    simulation_sent_count =
      PensionCase
      |> where_date_range(:simulation_sent_at, start_date, end_date)
      |> Repo.aggregate(:count)

    consultations_count =
      Consultation
      |> where_date_range(:assigned_at, start_date, end_date)
      |> Repo.aggregate(:count)

    paid_count =
      Consultation
      |> where_date_range(:assigned_at, start_date, end_date)
      |> where([c], c.payment_status in ["paid", "confirmed"])
      |> Repo.aggregate(:count)

    %{
      conversations: conversations_count,
      qualified: qualified_count,
      simulation_sent: simulation_sent_count,
      consultations: consultations_count,
      paid: paid_count,
      qualified_rate: pct(qualified_count, conversations_count),
      simulation_rate: pct(simulation_sent_count, qualified_count),
      consultation_rate: pct(consultations_count, simulation_sent_count),
      paid_rate: pct(paid_count, consultations_count),
      overall_conversion: pct(paid_count, conversations_count)
    }
  end

  def operations_metrics(start_date, end_date) do
    period =
      Consultation
      |> where_date_range(:assigned_at, start_date, end_date)

    active_count =
      Consultation
      |> where([c], c.status in ~w[pending assigned active])
      |> Repo.aggregate(:count)

    response_seconds =
      period
      |> where([c], not is_nil(c.accepted_at))
      |> select([c], avg(fragment("EXTRACT(EPOCH FROM (? - ?))", c.accepted_at, c.assigned_at)))
      |> Repo.one()

    avg_duration =
      period
      |> where([c], not is_nil(c.duration_minutes))
      |> select([c], avg(c.duration_minutes))
      |> Repo.one()

    avg_rating =
      period
      |> where([c], not is_nil(c.customer_rating))
      |> select([c], avg(c.customer_rating))
      |> Repo.one()

    rated_count =
      period
      |> where([c], not is_nil(c.customer_rating))
      |> Repo.aggregate(:count)

    video_count =
      period
      |> where([c], c.consultation_type == "video")
      |> Repo.aggregate(:count)

    total = Repo.aggregate(period, :count)

    %{
      active_consultations: active_count,
      total_consultations: total,
      avg_response_minutes: to_float(response_seconds) |> div_nil(60) |> round_to(1),
      avg_duration_minutes: to_float(avg_duration) |> round_to(1),
      avg_rating: to_float(avg_rating) |> round_to(2),
      rated_count: rated_count,
      video_count: video_count,
      video_adoption_rate: pct(video_count, total)
    }
  end

  def revenue_metrics(start_date, end_date) do
    paid =
      StripePayment
      |> where_date_range(:paid_at, start_date, end_date)
      |> where([p], p.status == "paid")

    total_revenue = Repo.aggregate(paid, :sum, :amount) || 0.0
    paid_count = Repo.aggregate(paid, :count)

    total_refunds =
      StripePayment
      |> where_date_range(:paid_at, start_date, end_date)
      |> where([p], p.status == "refunded")
      |> Repo.aggregate(:sum, :amount) || 0.0

    refund_count =
      StripePayment
      |> where_date_range(:paid_at, start_date, end_date)
      |> where([p], p.status == "refunded")
      |> Repo.aggregate(:count)

    total_fees =
      StripePayment
      |> where_date_range(:paid_at, start_date, end_date)
      |> where([p], p.status == "paid")
      |> where([p], not is_nil(p.stripe_fee))
      |> Repo.aggregate(:sum, :stripe_fee) || 0.0

    commission = total_revenue * @commission_rate
    agent_payout = total_revenue - commission
    avg_value = if paid_count > 0, do: total_revenue / paid_count, else: 0.0

    %{
      total_revenue: total_revenue,
      commission: commission,
      agent_payout: agent_payout,
      stripe_fees: total_fees,
      total_refunds: total_refunds,
      refund_count: refund_count,
      paid_count: paid_count,
      avg_consultation_value: avg_value,
      net_to_platform: commission - total_fees
    }
  end

  def pension_case_metrics(start_date, end_date) do
    base =
      PensionCase
      |> where_date_range(:created_at, start_date, end_date)

    total = Repo.aggregate(base, :count)
    qualified = base |> where([p], p.qualifies == true) |> Repo.aggregate(:count)
    disqualified = base |> where([p], p.qualifies == false) |> Repo.aggregate(:count)

    avg_delta =
      base
      |> where([p], not is_nil(p.simulation_delta_monthly))
      |> select([p], avg(p.simulation_delta_monthly))
      |> Repo.one()

    modalidad_mix =
      base
      |> where([p], not is_nil(p.recommended_modalidad))
      |> group_by([p], p.recommended_modalidad)
      |> select([p], %{modalidad: p.recommended_modalidad, count: count(p.id)})
      |> order_by([p], desc: count(p.id))
      |> Repo.all()

    %{
      total: total,
      qualified: qualified,
      disqualified: disqualified,
      unknown: total - qualified - disqualified,
      qualified_rate: pct(qualified, total),
      avg_pension_delta_monthly: to_float(avg_delta) |> round_to(0),
      modalidad_mix: modalidad_mix
    }
  end

  def daily_series(start_date, end_date) do
    days = Date.range(start_date, end_date) |> Enum.to_list()

    conv_by_day =
      Conversation
      |> where_date_range(:created_at, start_date, end_date)
      |> group_by([c], fragment("date(?)", c.created_at))
      |> select([c], {fragment("date(?)", c.created_at), count(c.id)})
      |> Repo.all()
      |> Map.new()

    consult_by_day =
      Consultation
      |> where_date_range(:assigned_at, start_date, end_date)
      |> group_by([c], fragment("date(?)", c.assigned_at))
      |> select([c], {fragment("date(?)", c.assigned_at), count(c.id)})
      |> Repo.all()
      |> Map.new()

    paid_by_day =
      Consultation
      |> where_date_range(:assigned_at, start_date, end_date)
      |> where([c], c.payment_status in ["paid", "confirmed"])
      |> group_by([c], fragment("date(?)", c.assigned_at))
      |> select([c], {fragment("date(?)", c.assigned_at), count(c.id)})
      |> Repo.all()
      |> Map.new()

    revenue_by_day =
      StripePayment
      |> where_date_range(:paid_at, start_date, end_date)
      |> where([p], p.status == "paid")
      |> group_by([p], fragment("date(?)", p.paid_at))
      |> select([p], {fragment("date(?)", p.paid_at), sum(p.amount)})
      |> Repo.all()
      |> Map.new()

    Enum.map(days, fn day ->
      %{
        date: day,
        conversations: Map.get(conv_by_day, day, 0),
        consultations: Map.get(consult_by_day, day, 0),
        paid: Map.get(paid_by_day, day, 0),
        revenue: to_float(Map.get(revenue_by_day, day, 0))
      }
    end)
  end

  def recent_consultations(limit) do
    Consultation
    |> order_by(desc: :assigned_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload([:customer, :agent])
  end

  @neon_cap_bytes 512 * 1024 * 1024

  def db_size do
    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), "SELECT pg_database_size(current_database()) AS size_bytes")
    bytes = result.rows |> List.first() |> List.first() || 0
    mb = Float.round(bytes / (1024 * 1024), 1)
    percent = Float.round(bytes / @neon_cap_bytes * 100, 1)

    %{bytes: bytes, mb: mb, cap_mb: 512, percent: percent}
  end

  def count_agents, do: Repo.aggregate(Agent, :count)

  def count_active_agents do
    Agent |> where([a], a.is_available == true) |> Repo.aggregate(:count)
  end

  # ── Private ────────────────────────────────────────────────────

  defp where_date_range(query, field, start_date, end_date) do
    start_naive = to_naive_start(start_date)
    end_naive = to_naive_end(end_date)

    from q in query,
      where: field(q, ^field) >= ^start_naive and field(q, ^field) <= ^end_naive
  end

  defp to_naive_start(%Date{} = d), do: NaiveDateTime.new!(d, ~T[00:00:00])
  defp to_naive_end(%Date{} = d), do: NaiveDateTime.new!(d, ~T[23:59:59])

  defp pct(_, 0), do: 0.0
  defp pct(_, nil), do: 0.0
  defp pct(n, d) when is_number(n) and is_number(d), do: Float.round(n / d * 100, 1)

  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(n) when is_float(n), do: n

  defp div_nil(n, d) when is_number(n) and is_number(d) and d != 0, do: n / d
  defp div_nil(_, _), do: 0.0

  defp round_to(n, decimals) when is_number(n), do: Float.round(n * 1.0, decimals)
end
