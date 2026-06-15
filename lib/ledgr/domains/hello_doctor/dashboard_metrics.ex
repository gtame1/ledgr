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

  # The dashboard owner's own patient row — used for development and
  # smoke-testing. Excluded from all funnel / cost / user metrics so they
  # reflect real customer activity only.
  @test_patient_id "2ed77952-cead-4bc4-bc44-51f5b5052d76"

  # GL account where Marketing & Advertising spend lands (see
  # hello_doctor_seeds.exs chart of accounts).
  @cac_account_code "6050"

  # Conversation funnel_stage values that mean the patient has already been
  # offered a doctor. `doctor_recommended` is the threshold; anything
  # downstream of it counts as "offered" too.
  @offered_or_downstream ~w[
    doctor_recommended consultation_type_set payment_link_sent
    payment_confirmed data_collected doctor_search doctor_connected
    consultation_complete consultation_failed
  ]

  # ── Public API ─────────────────────────────────────────────────

  @doc "Returns a complete metrics bundle for the dashboard."
  def all(start_date, end_date) do
    %{
      funnel: funnel_metrics(start_date, end_date),
      funnel_segments: funnel_by_segment(start_date, end_date),
      cost_metrics: cost_metrics(start_date, end_date),
      user_metrics: user_metrics(start_date, end_date),
      rating_metrics: rating_metrics(start_date, end_date),
      operations: operations_metrics(start_date, end_date),
      revenue: revenue_metrics(start_date, end_date),
      top_diagnoses: top_diagnoses(start_date, end_date, 10),
      prescription_mix: prescription_mix(start_date, end_date),
      conversations_per_patient: conversations_per_patient(start_date, end_date),
      return_cohorts: weekly_return_cohorts(start_date, end_date),
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

  @doc """
  Lightweight subset of `all/2` for period-over-period comparison: only the
  scalar operational figures the dashboard renders deltas on (funnel, ops,
  users). Skips the heavy `funnel_by_segment` / `infrastructure_costs` /
  `db_size` queries so the prior-period call stays cheap.
  """
  def period_summary(start_date, end_date) do
    %{
      funnel: funnel_metrics(start_date, end_date),
      operations: operations_metrics(start_date, end_date),
      user_metrics: user_metrics(start_date, end_date)
    }
  end

  # ── Weekly return-rate cohorts (vintage) ───────────────────────

  @doc """
  Return-rate cohorts grouped by weekly vintage.

  Each patient is assigned to a vintage = the ISO week (Mexico City) of
  their FIRST-ever conversation. For each vintage whose first conversation
  falls inside [start_date, end_date], returns:

    * `cohort_size` — patients first seen that week
    * `returned`    — how many of them started ≥1 additional conversation
    * `return_rate` — returned / cohort_size (%)

  "Returned" is measured across ALL of a patient's conversations, not just
  those in-period, so the rate reflects true repeat behaviour — which means
  the most recent weeks are still maturing (a patient acquired this week
  hasn't had much time to come back). Excludes the dashboard-owner test
  patient. Ordered newest vintage first.
  """
  def weekly_return_cohorts(start_date, end_date) do
    start_naive = to_naive_start(start_date)
    end_exclusive = to_naive_end_exclusive(end_date)

    sql = """
    WITH patient_convs AS (
      SELECT c.patient_id AS pid,
             MIN(c.created_at) AS first_at,
             COUNT(*) AS conv_count
      FROM conversations c
      WHERE c.patient_id IS NOT NULL
        AND c.patient_id != $1
      GROUP BY c.patient_id
    )
    SELECT
      date_trunc(
        'week',
        (first_at AT TIME ZONE 'UTC') AT TIME ZONE 'America/Mexico_City'
      )::date AS vintage_week,
      COUNT(*) AS cohort_size,
      COUNT(*) FILTER (WHERE conv_count >= 2) AS returned
    FROM patient_convs
    WHERE first_at >= $2 AND first_at < $3
    GROUP BY vintage_week
    ORDER BY vintage_week DESC
    """

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [
        @test_patient_id,
        start_naive,
        end_exclusive
      ])

    cohorts =
      Enum.map(rows, fn [week, size, returned] ->
        %{
          week_start: week,
          cohort_size: size,
          returned: returned,
          return_rate: pct(returned, size)
        }
      end)

    total_size = Enum.reduce(cohorts, 0, fn c, acc -> acc + c.cohort_size end)
    total_returned = Enum.reduce(cohorts, 0, fn c, acc -> acc + c.returned end)

    %{
      cohorts: cohorts,
      total_cohort: total_size,
      total_returned: total_returned,
      overall_rate: pct(total_returned, total_size)
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

  # ── Funnel by segment (new/existing user × tenant) ─────────────

  @doc """
  Returns a per-segment funnel: 4 groups keyed by `{user_type, tenant}`
  where `user_type` is `"new"` or `"existing"` (new = patient created in
  the same calendar month as the conversation) and `tenant` is the bot's
  tenant column (typically `"direct"` or `"mvp"`).

  Each group is a map with five counters plus conversion percentages:

      %{
        conversations: n,
        offered: n,           # doctor was recommended
        accepted: n,          # patient picked a consultation_type
        paid: n,              # stripe_payment_intent_id set
        completed: n,         # a consultation row reached completed_at
        offered_rate, accepted_rate, paid_rate, completed_rate,
        overall_conversion   # completed / conversations
      }

  Excludes the dashboard-owner test patient and any conversation tied to
  a bot test/bypass payment intent.
  """
  def funnel_by_segment(start_date, end_date) do
    start_naive = to_naive_start(start_date)
    end_exclusive = to_naive_end_exclusive(end_date)

    # Two perf notes:
    # 1. The "completed" leg used to be a per-row `WHERE EXISTS (...
    #    FROM consultations ...)` correlated subquery, which Postgres
    #    re-evaluates for every conversation. Pre-aggregating
    #    consultations to one row per conversation via a CTE (`conv_done`)
    #    turns it into a single LEFT JOIN — orders of magnitude faster
    #    once the table grows.
    # 2. Bump the pool timeout to 30s. The dashboard runs this on every
    #    page load and the default 15s wasn't enough during a cold start
    #    on Neon. The query itself shouldn't take that long after the
    #    rewrite, but the headroom prevents the page from 500ing during
    #    Neon autoresume.
    sql = """
    WITH conv_done AS (
      SELECT conversation_id,
             MAX(CASE WHEN completed_at IS NOT NULL THEN 1 ELSE 0 END) AS has_completed
      FROM consultations
      GROUP BY conversation_id
    )
    SELECT
      CASE
        WHEN p.id IS NULL THEN 'existing'
        WHEN date_trunc('month', p.created_at) = date_trunc('month', c.created_at)
          THEN 'new'
        ELSE 'existing'
      END AS user_type,
      COALESCE(c.tenant, 'unknown') AS tenant,
      COUNT(*) AS conversations,
      COUNT(*) FILTER (
        WHERE c.doctor_recommended OR c.funnel_stage = ANY($3::text[])
      ) AS offered,
      COUNT(*) FILTER (WHERE c.consultation_type IS NOT NULL) AS accepted,
      COUNT(*) FILTER (WHERE c.stripe_payment_intent_id IS NOT NULL) AS paid,
      COUNT(*) FILTER (WHERE cd.has_completed = 1) AS completed
    FROM conversations c
    LEFT JOIN patients p ON p.id = c.patient_id
    LEFT JOIN conv_done cd ON cd.conversation_id = c.id
    WHERE c.created_at >= $1 AND c.created_at < $2
      AND (c.patient_id IS NULL OR c.patient_id != $4)
      AND (
        c.stripe_payment_intent_id IS NULL
        OR (
          c.stripe_payment_intent_id NOT LIKE 'pi_test_bypass_%'
          AND c.stripe_payment_intent_id NOT LIKE 'cs_no_payment_%'
        )
      )
    GROUP BY user_type, tenant
    """

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo.active_repo(),
        sql,
        [
          start_naive,
          end_exclusive,
          @offered_or_downstream,
          @test_patient_id
        ],
        timeout: 30_000
      )

    rows
    |> Enum.map(fn [user_type, tenant, conv, off, acc, paid, done] ->
      {{user_type, tenant},
       %{
         conversations: conv,
         offered: off,
         accepted: acc,
         paid: paid,
         completed: done,
         offered_rate: pct(off, conv),
         accepted_rate: pct(acc, conv),
         paid_rate: pct(paid, conv),
         completed_rate: pct(done, conv),
         overall_conversion: pct(done, conv)
       }}
    end)
    |> Map.new()
  end

  # ── Cost metrics: cost per consult/conv, CAC ───────────────────

  @doc """
  Returns three cost ratios for the period:

    * `cost_per_consultation` = all GL expense debits / consultations
    * `cost_per_conversation` = all GL expense debits / conversations
    * `cac` = Marketing & Advertising (acct 6050) debits / new users

  All inputs exclude the dashboard-owner test patient and bot test/bypass
  consultations. Returned as MXN floats; nil when the denominator is 0.
  """
  def cost_metrics(start_date, end_date) do
    consultations = count_real_consultations(start_date, end_date)
    conversations = count_real_conversations(start_date, end_date)
    new_users = count_new_users(start_date, end_date)

    total_costs = expense_total_cents(start_date, end_date, nil) / 100.0
    marketing_costs = expense_total_cents(start_date, end_date, @cac_account_code) / 100.0

    %{
      total_costs_mxn: Float.round(total_costs, 2),
      marketing_costs_mxn: Float.round(marketing_costs, 2),
      consultations: consultations,
      conversations: conversations,
      new_users: new_users,
      cost_per_consultation: safe_div(total_costs, consultations),
      cost_per_conversation: safe_div(total_costs, conversations),
      cac: safe_div(marketing_costs, new_users)
    }
  end

  defp count_real_consultations(start_date, end_date) do
    start_naive = to_naive_start(start_date)
    end_exclusive = to_naive_end_exclusive(end_date)

    sql = """
    SELECT COUNT(*)
    FROM consultations cs
    WHERE cs.assigned_at >= $1 AND cs.assigned_at < $2
      AND (cs.patient_id IS NULL OR cs.patient_id != $3)
      AND (
        cs.stripe_payment_intent_id IS NULL
        OR (
          cs.stripe_payment_intent_id NOT LIKE 'pi_test_bypass_%'
          AND cs.stripe_payment_intent_id NOT LIKE 'cs_no_payment_%'
        )
      )
    """

    %{rows: [[n]]} =
      Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [
        start_naive,
        end_exclusive,
        @test_patient_id
      ])

    n
  end

  defp count_real_conversations(start_date, end_date) do
    start_naive = to_naive_start(start_date)
    end_exclusive = to_naive_end_exclusive(end_date)

    sql = """
    SELECT COUNT(*)
    FROM conversations c
    WHERE c.created_at >= $1 AND c.created_at < $2
      AND (c.patient_id IS NULL OR c.patient_id != $3)
    """

    %{rows: [[n]]} =
      Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [
        start_naive,
        end_exclusive,
        @test_patient_id
      ])

    n
  end

  # Returns the SUM of debit_cents on journal lines in the period,
  # optionally restricted to a single account code (for CAC).
  defp expense_total_cents(start_date, end_date, account_code) do
    base_sql = """
    SELECT COALESCE(SUM(jl.debit_cents), 0)
    FROM journal_entries je
    JOIN journal_lines jl ON jl.journal_entry_id = je.id
    JOIN accounts a       ON a.id = jl.account_id
    WHERE je.date >= $1 AND je.date <= $2
      AND a.type = 'expense'
    """

    {sql, params} =
      case account_code do
        nil -> {base_sql, [start_date, end_date]}
        code -> {base_sql <> " AND a.code = $3", [start_date, end_date, code]}
      end

    %{rows: [[n]]} = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, params)
    n
  end

  # ── User metrics ───────────────────────────────────────────────

  @doc """
  Returns counts and per-user averages for users active in the period:

    * `new_users`         — patients whose created_at falls inside the period
    * `existing_users`    — patients created BEFORE the period start
    * `total_active_users`— unique patients with at least one conversation
                            in the period (excluding test patient)
    * `conversations_per_existing` — avg conversations per existing user
                                     who had ≥1 conversation in the period
    * `consultations_per_existing` — same but for consultations
  """
  def user_metrics(start_date, end_date) do
    start_naive = to_naive_start(start_date)
    end_exclusive = to_naive_end_exclusive(end_date)

    new_users = count_new_users(start_date, end_date)
    existing_users = count_existing_users_active(start_date, end_date)

    convs_per_existing =
      avg_per_existing_user(
        :conversations,
        start_naive,
        end_exclusive,
        to_naive_start(start_date)
      )

    consults_per_existing =
      avg_per_existing_user(
        :consultations,
        start_naive,
        end_exclusive,
        to_naive_start(start_date)
      )

    %{
      new_users: new_users,
      existing_users: existing_users,
      total_active_users: new_users + existing_users,
      conversations_per_existing: convs_per_existing,
      consultations_per_existing: consults_per_existing
    }
  end

  defp count_new_users(start_date, end_date) do
    start_naive = to_naive_start(start_date)
    end_exclusive = to_naive_end_exclusive(end_date)

    sql = """
    SELECT COUNT(DISTINCT p.id)
    FROM patients p
    JOIN conversations c ON c.patient_id = p.id
    WHERE c.created_at >= $1 AND c.created_at < $2
      AND p.id != $3
      AND p.created_at >= $1 AND p.created_at < $2
    """

    %{rows: [[n]]} =
      Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [
        start_naive,
        end_exclusive,
        @test_patient_id
      ])

    n
  end

  defp count_existing_users_active(start_date, end_date) do
    start_naive = to_naive_start(start_date)
    end_exclusive = to_naive_end_exclusive(end_date)

    sql = """
    SELECT COUNT(DISTINCT p.id)
    FROM patients p
    JOIN conversations c ON c.patient_id = p.id
    WHERE c.created_at >= $1 AND c.created_at < $2
      AND p.id != $3
      AND p.created_at < $1
    """

    %{rows: [[n]]} =
      Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [
        start_naive,
        end_exclusive,
        @test_patient_id
      ])

    n
  end

  defp avg_per_existing_user(:conversations, start_naive, end_exclusive, period_start) do
    sql = """
    WITH per_user AS (
      SELECT p.id, COUNT(c.id) AS n
      FROM patients p
      JOIN conversations c ON c.patient_id = p.id
      WHERE c.created_at >= $1 AND c.created_at < $2
        AND p.id != $3
        AND p.created_at < $4
      GROUP BY p.id
    )
    SELECT COALESCE(AVG(n), 0)::float FROM per_user
    """

    %{rows: [[avg]]} =
      Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [
        start_naive,
        end_exclusive,
        @test_patient_id,
        period_start
      ])

    Float.round(to_float(avg), 2)
  end

  defp avg_per_existing_user(:consultations, start_naive, end_exclusive, period_start) do
    sql = """
    WITH per_user AS (
      SELECT p.id, COUNT(cs.id) AS n
      FROM patients p
      JOIN consultations cs ON cs.patient_id = p.id
      WHERE cs.assigned_at >= $1 AND cs.assigned_at < $2
        AND p.id != $3
        AND p.created_at < $4
        AND (
          cs.stripe_payment_intent_id IS NULL
          OR (
            cs.stripe_payment_intent_id NOT LIKE 'pi_test_bypass_%'
            AND cs.stripe_payment_intent_id NOT LIKE 'cs_no_payment_%'
          )
        )
      GROUP BY p.id
    )
    SELECT COALESCE(AVG(n), 0)::float FROM per_user
    """

    %{rows: [[avg]]} =
      Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [
        start_naive,
        end_exclusive,
        @test_patient_id,
        period_start
      ])

    Float.round(to_float(avg), 2)
  end

  # ── Rating metrics: 4 dimensions ───────────────────────────────

  @doc """
  Returns avg ratings on the four dimensions captured by the bot:

    * `:doctor` — patient rating the doctor (consultations.patient_rating)
    * `:patient` — doctor rating the patient (consultations.doctor_rating)
    * `:platform_by_patient` — patient rating the platform
    * `:platform_by_doctor` — doctor rating the platform

  Each value is `%{avg: float|nil, count: int}` so the template can show
  "—" when there are zero ratings instead of a misleading 0.0.

  Excludes the dashboard-owner test patient.
  """
  def rating_metrics(start_date, end_date) do
    start_naive = to_naive_start(start_date)
    end_exclusive = to_naive_end_exclusive(end_date)

    sql = """
    SELECT
      AVG(cs.patient_rating)::float          AS doctor_avg,
      COUNT(cs.patient_rating)               AS doctor_n,
      AVG(cs.doctor_rating)::float           AS patient_avg,
      COUNT(cs.doctor_rating)                AS patient_n,
      AVG(cs.patient_platform_rating)::float AS pp_avg,
      COUNT(cs.patient_platform_rating)      AS pp_n,
      AVG(cs.doctor_platform_rating)::float  AS dp_avg,
      COUNT(cs.doctor_platform_rating)       AS dp_n
    FROM consultations cs
    WHERE cs.assigned_at >= $1 AND cs.assigned_at < $2
      AND (cs.patient_id IS NULL OR cs.patient_id != $3)
    """

    %{rows: [[d_avg, d_n, p_avg, p_n, pp_avg, pp_n, dp_avg, dp_n]]} =
      Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [
        start_naive,
        end_exclusive,
        @test_patient_id
      ])

    %{
      doctor: %{avg: rating_round(d_avg), count: d_n},
      patient: %{avg: rating_round(p_avg), count: p_n},
      platform_by_patient: %{avg: rating_round(pp_avg), count: pp_n},
      platform_by_doctor: %{avg: rating_round(dp_avg), count: dp_n}
    }
  end

  defp rating_round(nil), do: nil
  defp rating_round(n), do: Float.round(to_float(n), 2)

  defp safe_div(_n, 0), do: nil
  defp safe_div(_n, nil), do: nil

  defp safe_div(n, d) when is_number(n) and is_number(d) and d > 0,
    do: Float.round(n / d, 2)

  defp safe_div(_, _), do: nil

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

    avg =
      if total_patients > 0, do: Float.round(total_conversations / total_patients, 1), else: 0.0

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
        on:
          c.doctor_id == d.id and c.assigned_at >= ^to_naive_start(start_date) and
            c.assigned_at < ^to_naive_end_exclusive(end_date),
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
        on:
          c.doctor_id == d.id and
            c.assigned_at >= ^to_naive_start(start_date) and
            c.assigned_at < ^to_naive_end_exclusive(end_date),
        group_by: d.id,
        select: %{
          id: d.id,
          name: d.name,
          total: count(c.id),
          targeted:
            sum(fragment("CASE WHEN ? IS NOT NULL THEN 1 ELSE 0 END", c.targeted_doctor_id))
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

    by_service =
      Map.new(rows, fn r -> {r.service, %{total_usd: to_float(r.total_usd), rows: r.rows}} end)

    total_usd = Enum.reduce(rows, 0.0, fn r, acc -> acc + to_float(r.total_usd) end)

    # Per-service detail rows for the period (for the cost breakdown table)
    detail =
      ExternalCost
      |> where([c], c.date >= ^start_date and c.date <= ^end_date)
      |> order_by([c], asc: :service, asc: :date)
      |> select([c], %{
        id: c.id,
        service: c.service,
        date: c.date,
        model: c.model,
        amount_usd: c.amount_usd,
        units: c.units,
        unit_type: c.unit_type,
        posted_at: c.posted_at,
        journal_entry_id: c.journal_entry_id
      })
      |> Repo.all()

    %{
      total_usd: Float.round(total_usd, 4),
      openai: Map.get(by_service, "openai", %{total_usd: 0.0, rows: 0}),
      whereby: Map.get(by_service, "whereby", %{total_usd: 0.0, rows: 0}),
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

    # `fragment("date(?)", utc_naive)` extracts the UTC calendar date,
    # which is wrong by one day for any Mexico-evening activity (a
    # consultation at 9pm MX gets bucketed into tomorrow). Shift the
    # naive UTC value to Mexico City wall-clock first, then take the
    # date. Same conversion as Ledgr.Domains.HelloDoctor.to_mx_date/1,
    # just at the SQL layer.
    conv_by_day =
      Conversation
      |> where_date_range(:created_at, start_date, end_date)
      |> group_by(
        [c],
        fragment("date((? AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City'))", c.created_at)
      )
      |> select(
        [c],
        {fragment(
           "date((? AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City'))",
           c.created_at
         ), count(c.id)}
      )
      |> Repo.all()
      |> Map.new()

    consult_by_day =
      Consultation
      |> where_date_range(:assigned_at, start_date, end_date)
      |> group_by(
        [c],
        fragment("date((? AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City'))", c.assigned_at)
      )
      |> select(
        [c],
        {fragment(
           "date((? AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City'))",
           c.assigned_at
         ), count(c.id)}
      )
      |> Repo.all()
      |> Map.new()

    paid_by_day =
      Consultation
      |> where_date_range(:assigned_at, start_date, end_date)
      |> where([c], c.payment_status in ["paid", "confirmed"])
      |> group_by(
        [c],
        fragment("date((? AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City'))", c.assigned_at)
      )
      |> select(
        [c],
        {fragment(
           "date((? AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City'))",
           c.assigned_at
         ), count(c.id)}
      )
      |> Repo.all()
      |> Map.new()

    revenue_by_day =
      StripePayment
      |> where_date_range(:paid_at, start_date, end_date)
      |> where([p], p.status == "paid")
      |> group_by(
        [p],
        fragment("date((? AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City'))", p.paid_at)
      )
      |> select(
        [p],
        {fragment("date((? AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City'))", p.paid_at),
         sum(p.amount)}
      )
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

  Shows total billed, doctor share (flat $100 MXN per paid consultation),
  Stripe fees, and HD net (billed − doctor share − fees). Sourced from
  StripePayments linked to consultations — only includes consultations that
  have a linked paid Stripe payment.
  """
  def doctor_payout_report(start_date, end_date) do
    doctor_share_pesos =
      Ledgr.Domains.HelloDoctor.ConsultationAccounting.doctor_share_mxn()

    per_doctor =
      from d in Doctor,
        join: c in Consultation,
        on: c.doctor_id == d.id,
        join: p in StripePayment,
        on: p.consultation_id == c.id and p.status == "paid",
        where:
          p.paid_at >= ^to_naive_start(start_date) and
            p.paid_at < ^to_naive_end_exclusive(end_date),
        group_by: [d.id, d.name, d.specialty],
        select: %{
          id: d.id,
          name: d.name,
          specialty: d.specialty,
          consultation_count: count(c.id),
          total_billed: sum(p.amount),
          stripe_fees: sum(fragment("COALESCE(?, 0)", p.stripe_fee))
        },
        order_by: [desc: sum(p.amount)]

    rows =
      per_doctor
      |> Repo.all()
      |> Enum.map(fn row ->
        total = to_float(row.total_billed)
        fees = to_float(row.stripe_fees)
        share = row.consultation_count * doctor_share_pesos

        Map.merge(row, %{
          total_billed: total,
          doctor_share: Float.round(share, 2),
          stripe_fees: Float.round(fees, 2),
          net_to_hd: Float.round(total - share - fees, 2)
        })
      end)

    total_billed = Enum.reduce(rows, 0.0, &(&2 + &1.total_billed))
    total_doctor_share = Enum.reduce(rows, 0.0, &(&2 + &1.doctor_share))
    total_stripe_fees = Enum.reduce(rows, 0.0, &(&2 + &1.stripe_fees))

    %{
      rows: rows,
      total_billed: Float.round(total_billed, 2),
      total_doctor_share: Float.round(total_doctor_share, 2),
      total_stripe_fees: Float.round(total_stripe_fees, 2),
      total_net_to_hd: Float.round(total_billed - total_doctor_share - total_stripe_fees, 2)
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

  # 512 MB
  @neon_cap_bytes 512 * 1024 * 1024

  @doc "Returns current database size and % of Neon's 512 MB cap."
  def db_size do
    result =
      Ecto.Adapters.SQL.query!(
        Repo.active_repo(),
        "SELECT pg_database_size(current_database()) AS size_bytes"
      )

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

  # All timestamp columns are UTC-stored `timestamp without time zone` and
  # all input dates are Mexico City wall-clock. We MUST convert the date
  # bounds to UTC instants before comparing. Half-open `>= start AND <
  # end_exclusive` is the safe shape — the legacy `<= 23:59:59` pattern
  # both treated MX dates as UTC AND dropped the final second-of-day.
  # See Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive/1.
  defp where_date_range(query, field, start_date, end_date) do
    start_naive = to_naive_start(start_date)
    end_exclusive = to_naive_end_exclusive(end_date)

    from q in query,
      where: field(q, ^field) >= ^start_naive and field(q, ^field) < ^end_exclusive
  end

  defp to_naive_start(%Date{} = d),
    do: Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive(d)

  defp to_naive_end_exclusive(%Date{} = d),
    do: Ledgr.Domains.HelloDoctor.mx_day_end_utc_naive(d)

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
