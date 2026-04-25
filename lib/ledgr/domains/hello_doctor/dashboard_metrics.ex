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
  alias Ledgr.Domains.HelloDoctor.ExternalCosts.ExternalCost

  @commission_rate 0.15

  # ── Public API ─────────────────────────────────────────────────

  @doc "Returns a complete metrics bundle for the dashboard."
  def all(start_date, end_date) do
    %{
      funnel: funnel_metrics(start_date, end_date),
      operations: operations_metrics(start_date, end_date),
      revenue: revenue_metrics(start_date, end_date),
      top_diagnoses: top_diagnoses(start_date, end_date, 10),
      prescription_mix: prescription_mix(start_date, end_date),
      conversations_per_patient: conversations_per_patient(start_date, end_date),
      top_doctors: top_doctors_with_ratings(10, start_date, end_date),
      direct_requests: direct_request_metrics(start_date, end_date),
      infrastructure_costs: infrastructure_costs(start_date, end_date),
      daily_series: daily_series(start_date, end_date),
      # Infrastructure
      db_size: db_size(),
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

  @doc """
  Returns the breakdown of recipes by whether they require a formal prescription.
  %{requires: N, does_not_require: N, unknown: N, total: N, requires_rate: %}
  """
  def prescription_mix(start_date, end_date) do
    base =
      Prescription
      |> where_date_range(:created_at, start_date, end_date)

    total = Repo.aggregate(base, :count)

    requires =
      base
      |> where([p], p.requires_prescription == true)
      |> Repo.aggregate(:count)

    does_not_require =
      base
      |> where([p], p.requires_prescription == false)
      |> Repo.aggregate(:count)

    unknown = total - requires - does_not_require

    %{
      total: total,
      requires: requires,
      does_not_require: does_not_require,
      unknown: unknown,
      requires_rate: pct(requires, total)
    }
  end

  # ── Top doctors with ratings ───────────────────────────────────

  @doc """
  Returns a distribution of conversations per patient. Groups patients by
  their conversation count and returns bucket labels + counts.
  e.g. [%{bucket: "1", count: 45}, %{bucket: "2", count: 12}, %{bucket: "3+", count: 5}]
  Also returns avg and total unique patients.
  """
  def conversations_per_patient(start_date, end_date) do
    # Count conversations per patient in the period
    per_patient =
      Conversation
      |> where_date_range(:created_at, start_date, end_date)
      |> group_by([c], c.patient_id)
      |> select([c], %{patient_id: c.patient_id, count: count(c.id)})
      |> Repo.all()

    total_patients = length(per_patient)
    total_conversations = Enum.reduce(per_patient, 0, fn p, acc -> acc + p.count end)
    avg = if total_patients > 0, do: Float.round(total_conversations / total_patients, 1), else: 0.0

    # Build distribution buckets: 1, 2, 3, 4, 5+
    buckets =
      per_patient
      |> Enum.group_by(fn p -> min(p.count, 5) end)
      |> Enum.map(fn {bucket, patients} ->
        label = if bucket >= 5, do: "5+", else: "#{bucket}"
        %{bucket: label, bucket_num: bucket, count: length(patients)}
      end)
      |> Enum.sort_by(& &1.bucket_num)

    %{
      distribution: buckets,
      total_patients: total_patients,
      total_conversations: total_conversations,
      avg: avg
    }
  end

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

  # ── Direct doctor requests ─────────────────────────────────────

  @doc """
  Returns overall % of consultations where the patient requested a specific
  doctor (targeted_doctor_id IS NOT NULL), plus a per-doctor breakdown.
  """
  def direct_request_metrics(start_date, end_date) do
    total =
      Consultation
      |> where_date_range(:assigned_at, start_date, end_date)
      |> Repo.aggregate(:count)

    targeted =
      Consultation
      |> where_date_range(:assigned_at, start_date, end_date)
      |> where([c], not is_nil(c.targeted_doctor_id))
      |> Repo.aggregate(:count)

    per_doctor_query =
      from d in Doctor,
        join: c in Consultation,
          on: c.doctor_id == d.id
            and c.assigned_at >= ^to_naive_start(start_date)
            and c.assigned_at <= ^to_naive_end(end_date),
        group_by: d.id,
        select: %{
          id: d.id,
          name: d.name,
          total: count(c.id),
          targeted: sum(fragment("CASE WHEN ? IS NOT NULL THEN 1 ELSE 0 END", c.targeted_doctor_id))
        },
        order_by: [desc: count(c.id)]

    per_doctor =
      per_doctor_query
      |> Repo.all()
      |> Enum.map(fn row ->
        t = row.targeted || 0
        Map.put(row, :targeted_rate, pct(t, row.total))
      end)

    %{
      total: total,
      targeted: targeted,
      targeted_rate: pct(targeted, total),
      per_doctor: per_doctor
    }
  end

  # ── Infrastructure costs ───────────────────────────────────────

  @doc """
  Aggregates external service costs for the given date range.
  Returns totals per service and a combined total_usd.
  """
  def infrastructure_costs(start_date, end_date) do
    rows =
      ExternalCost
      |> where([c], c.date >= ^start_date and c.date <= ^end_date)
      |> group_by([c], c.service)
      |> select([c], %{service: c.service, total_usd: sum(c.amount_usd), rows: count(c.id)})
      |> Repo.all()

    by_service = Map.new(rows, fn r -> {r.service, %{total_usd: to_float(r.total_usd), rows: r.rows}} end)

    total_usd = Enum.reduce(rows, 0.0, fn r, acc -> acc + to_float(r.total_usd) end)

    # Per-service detail rows for the period (for the cost breakdown table)
    detail =
      ExternalCost
      |> where([c], c.date >= ^start_date and c.date <= ^end_date)
      |> order_by([c], [asc: :service, asc: :date])
      |> select([c], %{
        id:               c.id,
        service:          c.service,
        date:             c.date,
        model:            c.model,
        amount_usd:       c.amount_usd,
        units:            c.units,
        unit_type:        c.unit_type,
        posted_at:        c.posted_at,
        journal_entry_id: c.journal_entry_id
      })
      |> Repo.all()

    %{
      total_usd: Float.round(total_usd, 4),
      openai:       Map.get(by_service, "openai",        %{total_usd: 0.0, rows: 0}),
      whereby:      Map.get(by_service, "whereby",       %{total_usd: 0.0, rows: 0}),
      aws_app_runner: Map.get(by_service, "aws_app_runner", %{total_usd: 0.0, rows: 0}),
      detail: detail,
      last_synced: last_synced_at()
    }
  end

  defp last_synced_at do
    ExternalCost
    |> select([c], max(c.synced_at))
    |> Repo.one()
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

  # ── Doctor payout report ───────────────────────────────────────

  @doc """
  Returns per-doctor payout breakdown for the given period.
  Shows total billed, doctor share (85%), and consultation count.
  Sourced from StripePayments linked to consultations — only includes
  consultations that have a linked paid Stripe payment.
  """
  def doctor_payout_report(start_date, end_date) do
    per_doctor =
      from d in Doctor,
        join: c in Consultation,
          on: c.doctor_id == d.id,
        join: p in StripePayment,
          on: p.consultation_id == c.id and p.status == "paid",
        where: p.paid_at >= ^to_naive_start(start_date) and p.paid_at <= ^to_naive_end(end_date),
        group_by: [d.id, d.name, d.specialty],
        select: %{
          id:                  d.id,
          name:                d.name,
          specialty:           d.specialty,
          consultation_count:  count(c.id),
          total_billed:        sum(p.amount),
          doctor_share:        sum(p.amount) * 0.85,
          stripe_fees:         sum(fragment("COALESCE(?, 0)", p.stripe_fee))
        },
        order_by: [desc: sum(p.amount)]

    rows =
      per_doctor
      |> Repo.all()
      |> Enum.map(fn row ->
        total = to_float(row.total_billed)
        share = to_float(row.doctor_share)
        fees  = to_float(row.stripe_fees)
        Map.merge(row, %{
          total_billed:  total,
          doctor_share:  Float.round(share, 2),
          stripe_fees:   Float.round(fees, 2),
          net_to_hd:     Float.round(total * 0.15 - fees, 2)
        })
      end)

    total_billed = Enum.reduce(rows, 0.0, & &2 + &1.total_billed)
    total_doctor_share = Enum.reduce(rows, 0.0, & &2 + &1.doctor_share)
    total_stripe_fees  = Enum.reduce(rows, 0.0, & &2 + &1.stripe_fees)

    %{
      rows: rows,
      total_billed:       Float.round(total_billed, 2),
      total_doctor_share: Float.round(total_doctor_share, 2),
      total_stripe_fees:  Float.round(total_stripe_fees, 2),
      total_net_to_hd:    Float.round(total_billed * 0.15 - total_stripe_fees, 2)
    }
  end

  # ── Helpers ────────────────────────────────────────────────────

  def recent_consultations(limit) do
    Consultation
    |> order_by(desc: :assigned_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload([:patient, :doctor])
  end

  @neon_cap_bytes 512 * 1024 * 1024  # 512 MB

  @doc "Returns current database size and % of Neon's 512 MB cap."
  def db_size do
    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), "SELECT pg_database_size(current_database()) AS size_bytes")
    bytes = result.rows |> List.first() |> List.first() || 0
    mb = Float.round(bytes / (1024 * 1024), 1)
    percent = Float.round(bytes / @neon_cap_bytes * 100, 1)

    %{bytes: bytes, mb: mb, cap_mb: 512, percent: percent}
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
