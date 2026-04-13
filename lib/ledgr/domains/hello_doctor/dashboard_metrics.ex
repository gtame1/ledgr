defmodule Ledgr.Domains.HelloDoctor.DashboardMetrics do
  @moduledoc """
  Aggregate operational metrics for the HelloDoctor dashboard.

  Organized by business concern:
  - funnel_metrics: conversations → doctor recommended → consultation → paid
  - operations_metrics: active consultations, avg response time, duration, ratings
  - revenue_metrics: payments, commission, refunds
  - top_diagnoses: most common diagnoses from prescriptions
  - daily_series: per-day time series for charts
  """

  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
  alias Ledgr.Domains.HelloDoctor.Conversations.Conversation
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.Prescriptions.Prescription
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment

  @commission_rate 0.15

  # ── Public API ─────────────────────────────────────────────────

  @doc "Returns a complete metrics bundle for the dashboard."
  def all(start_date, end_date) do
    %{
      funnel: funnel_metrics(start_date, end_date),
      operations: operations_metrics(start_date, end_date),
      revenue: revenue_metrics(start_date, end_date),
      top_diagnoses: top_diagnoses(start_date, end_date, 10),
      top_doctors: top_doctors_with_ratings(10, start_date, end_date),
      daily_series: daily_series(start_date, end_date),
      recent_consultations: recent_consultations(6),
      # Totals independent of period (for footer/nav context)
      total_doctors: count_doctors(),
      active_doctors: count_active_doctors()
    }
  end

  # ── Funnel ─────────────────────────────────────────────────────

  def funnel_metrics(start_date, end_date) do
    conversations_count =
      Conversation
      |> where_date_range(:created_at, start_date, end_date)
      |> Repo.aggregate(:count)

    doctor_recommended_count =
      Conversation
      |> where_date_range(:created_at, start_date, end_date)
      |> where([c], c.doctor_recommended == true)
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
      doctor_recommended: doctor_recommended_count,
      consultations: consultations_count,
      paid: paid_count,
      doctor_recommended_rate: pct(doctor_recommended_count, conversations_count),
      consultation_rate: pct(consultations_count, doctor_recommended_count),
      paid_rate: pct(paid_count, consultations_count),
      overall_conversion: pct(paid_count, conversations_count)
    }
  end

  # ── Operations ─────────────────────────────────────────────────

  def operations_metrics(start_date, end_date) do
    period_consults =
      Consultation
      |> where_date_range(:assigned_at, start_date, end_date)

    active_count =
      Consultation
      |> where([c], c.status in ~w[pending assigned active])
      |> Repo.aggregate(:count)

    # Response time (assigned -> accepted), in minutes
    response_time_seconds =
      period_consults
      |> where([c], not is_nil(c.accepted_at))
      |> select([c], avg(fragment("EXTRACT(EPOCH FROM (? - ?))", c.accepted_at, c.assigned_at)))
      |> Repo.one()

    avg_duration =
      period_consults
      |> where([c], not is_nil(c.duration_minutes))
      |> select([c], avg(c.duration_minutes))
      |> Repo.one()

    avg_rating =
      period_consults
      |> where([c], not is_nil(c.patient_rating))
      |> select([c], avg(c.patient_rating))
      |> Repo.one()

    rated_count =
      period_consults
      |> where([c], not is_nil(c.patient_rating))
      |> Repo.aggregate(:count)

    video_consults =
      period_consults
      |> where([c], c.consultation_type == "video")
      |> Repo.aggregate(:count)

    total_consults = Repo.aggregate(period_consults, :count)

    %{
      active_consultations: active_count,
      total_consultations: total_consults,
      avg_response_minutes: to_float(response_time_seconds) |> div_nil(60) |> round_to(1),
      avg_duration_minutes: to_float(avg_duration) |> round_to(1),
      avg_rating: to_float(avg_rating) |> round_to(2),
      rated_count: rated_count,
      video_count: video_consults,
      video_adoption_rate: pct(video_consults, total_consults)
    }
  end

  # ── Revenue ────────────────────────────────────────────────────

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
    doctor_payout = total_revenue - commission
    avg_value = if paid_count > 0, do: total_revenue / paid_count, else: 0.0

    %{
      total_revenue: total_revenue,
      commission: commission,
      doctor_payout: doctor_payout,
      stripe_fees: total_fees,
      total_refunds: total_refunds,
      refund_count: refund_count,
      paid_count: paid_count,
      avg_consultation_value: avg_value,
      net_to_hellodoctor: commission - total_fees
    }
  end

  # ── Top diagnoses ──────────────────────────────────────────────

  def top_diagnoses(start_date, end_date, limit \\ 10) do
    Prescription
    |> where_date_range(:created_at, start_date, end_date)
    |> where([p], not is_nil(p.diagnosis) and p.diagnosis != "")
    |> group_by([p], p.diagnosis)
    |> select([p], %{diagnosis: p.diagnosis, count: count(p.id)})
    |> order_by([p], desc: count(p.id))
    |> limit(^limit)
    |> Repo.all()
  end

  # ── Top doctors with ratings ───────────────────────────────────

  def top_doctors_with_ratings(limit, start_date, end_date) do
    query =
      from d in Doctor,
        left_join: c in Consultation,
          on: c.doctor_id == d.id and c.assigned_at >= ^to_naive_start(start_date)
                                and c.assigned_at <= ^to_naive_end(end_date),
        group_by: d.id,
        select: %{
          id: d.id,
          name: d.name,
          specialty: d.specialty,
          consultation_count: count(c.id),
          avg_rating: avg(c.patient_rating),
          is_available: d.is_available
        },
        order_by: [desc: count(c.id)],
        limit: ^limit

    Repo.all(query)
  end

  # ── Daily time series ──────────────────────────────────────────

  @doc """
  Returns a list of %{date, conversations, consultations, paid, revenue} for each
  day in [start_date, end_date]. Days with no data have zero values.
  """
  def daily_series(start_date, end_date) do
    days = date_range(start_date, end_date)

    # Fetch aggregates grouped by day
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

  # ── Helpers ────────────────────────────────────────────────────

  def recent_consultations(limit) do
    Consultation
    |> order_by(desc: :assigned_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload([:patient, :doctor])
  end

  def count_doctors, do: Repo.aggregate(Doctor, :count)

  def count_active_doctors do
    Doctor |> where([d], d.is_available == true) |> Repo.aggregate(:count)
  end

  # ── Private helpers ────────────────────────────────────────────

  defp where_date_range(query, field, start_date, end_date) do
    start_naive = to_naive_start(start_date)
    end_naive = to_naive_end(end_date)

    from q in query,
      where: field(q, ^field) >= ^start_naive and field(q, ^field) <= ^end_naive
  end

  defp to_naive_start(%Date{} = d), do: NaiveDateTime.new!(d, ~T[00:00:00])
  defp to_naive_end(%Date{} = d), do: NaiveDateTime.new!(d, ~T[23:59:59])

  defp date_range(start_date, end_date) do
    Date.range(start_date, end_date) |> Enum.to_list()
  end

  defp pct(_, 0), do: 0.0
  defp pct(_, nil), do: 0.0
  defp pct(numerator, denominator) when is_number(numerator) and is_number(denominator) do
    Float.round(numerator / denominator * 100, 1)
  end

  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(n) when is_float(n), do: n

  defp div_nil(n, d) when is_number(n) and is_number(d) and d != 0, do: n / d
  defp div_nil(_, _), do: 0.0

  defp round_to(n, decimals) when is_number(n), do: Float.round(n * 1.0, decimals)
end
