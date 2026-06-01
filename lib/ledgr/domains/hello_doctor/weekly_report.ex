defmodule Ledgr.Domains.HelloDoctor.WeeklyReport do
  @moduledoc """
  Weekly doctor payouts report — per-consultation rows showing what's
  still owed to each doctor net of payouts already made and retentions
  due / applied.

  Per consultation:

      doctor_share              = flat 100 MXN (per-consult fee)
      iva_retention_to_apply    = 0 (IVA rate currently 0 for honorarios)
      isr_retention_to_apply    = 2.5 if doctor.has_correct_rfc, else 20

      paid_out_amount           = Σ doctor_payouts.amount_cents
      iva_retentions_applied    = Σ doctor_payouts.iva_retention_cents
      isr_retentions_applied    = Σ doctor_payouts.isr_retention_cents
        (all summed across the consultation's linked doctor_payouts)

      owed_to_doctor       = doctor_share - paid_out_amount
      net_payment_pending  = owed_to_doctor
                           - (iva_retention_to_apply - iva_retentions_applied)
                           - (isr_retention_to_apply - isr_retentions_applied)

  Rows with `net_payment_pending == 0` are filtered out by default —
  pass `include_settled: true` (or `?include_settled=true` on the URL)
  to keep them in the listing.

  Excludes:
    * test patient (`@test_patient_id`)
    * test doctor (`@test_doctor_id`)

  Period defaults to the previous full week (Mon–Sun) in Mexico City
  time.
  """

  alias Ledgr.Repo

  @doctor_share_mxn 100.0

  # Mexican payroll retention rates. ISR depends on whether we've
  # verified the doctor's RFC (registered honorarios get the lower
  # 2.5% retention rate; otherwise we hold back the 20% default).
  # Stored as percentage points so the value matches the report column.
  @iva_rate_pct 0.0
  @isr_rate_with_rfc_pct 2.5
  @isr_rate_without_rfc_pct 20.0

  # Excluded from every report — Guillermo's test patient + a test
  # doctor account. Both bot-managed, so we can't tag them in-schema;
  # hardcoded here is the simplest gate.
  @test_patient_id "2ed77952-cead-4bc4-bc44-51f5b5052d76"
  @test_doctor_id "03f3b382-3ae3-4c0c-8d8e-2382b241b1d8"

  # ── Period helpers ─────────────────────────────────────────────

  @doc "Returns {start_date, end_date} for the previous Mon–Sun week."
  def last_week_range do
    today = Ledgr.Domains.HelloDoctor.today()
    monday_this_week = Date.beginning_of_week(today, :monday)
    start_date = Date.add(monday_this_week, -7)
    end_date = Date.add(start_date, 6)
    {start_date, end_date}
  end

  # ── Main API ───────────────────────────────────────────────────

  @doc """
  Generates the weekly report for the given period.

  Options:
    * `:include_settled` — when `true`, includes consultations with
      `net_payment_pending == 0`. Defaults to `false` (filter them out).

  Returns a map:

      %{
        period: {start_date, end_date},
        include_settled?: boolean,
        consultations: [...],   # one row per attended consultation
        per_doctor:    [...],   # aggregated by doctor
        totals: %{...}
      }
  """
  def generate(start_date, end_date, opts \\ []) do
    include_settled? = Keyword.get(opts, :include_settled, false)

    consultations =
      start_date
      |> list_attended_consultations(end_date)
      |> maybe_filter_settled(include_settled?)

    per_doctor = aggregate_by_doctor(consultations)
    totals = totals(consultations, per_doctor)

    %{
      period: {start_date, end_date},
      include_settled?: include_settled?,
      consultations: consultations,
      per_doctor: per_doctor,
      totals: totals
    }
  end

  defp maybe_filter_settled(rows, true), do: rows

  defp maybe_filter_settled(rows, false),
    do: Enum.reject(rows, &(&1.net_payment_pending == 0.0))

  # ── Per-consultation query ─────────────────────────────────────

  @doc """
  Returns one row per completed consultation in
  `[start_date, end_date]` (by `completed_at`), with the full
  per-consultation payout picture: doctor share, retentions to apply,
  amounts already paid out, retentions already applied, and the
  derived `owed_to_doctor` / `net_payment_pending`.

  Excludes the test patient + test doctor account.

  Multi-payout per consultation is handled by aggregating
  `doctor_payouts` in a CTE before joining, so each consultation
  appears at most once (modulo multiple `stripe_payments` rows, which
  remain a degenerate case we accept).
  """
  def list_attended_consultations(start_date, end_date) do
    start_naive = NaiveDateTime.new!(start_date, ~T[00:00:00])
    end_naive = NaiveDateTime.new!(end_date, ~T[23:59:59])

    sql = """
    WITH payout_totals AS (
      SELECT
        dpc.consultation_id,
        SUM(dp.amount_cents)::bigint                       AS paid_out_cents,
        SUM(COALESCE(dp.iva_retention_cents, 0))::bigint   AS iva_applied_cents,
        SUM(COALESCE(dp.isr_retention_cents, 0))::bigint   AS isr_applied_cents,
        MAX(dp.payout_date)                                AS payout_date
      FROM doctor_payout_consultations dpc
      JOIN doctor_payouts dp ON dp.id = dpc.doctor_payout_id
      GROUP BY dpc.consultation_id
    )
    SELECT
      c.id                                                 AS consultation_id,
      c.completed_at,
      c.assigned_at,
      c.duration_minutes,
      c.consultation_type,
      c.payment_status,
      c.payment_amount,
      c.patient_rating,
      d.id                                                 AS doctor_id,
      d.name                                               AS doctor_name,
      d.specialty                                          AS doctor_specialty,
      COALESCE(d.has_correct_rfc, FALSE)                   AS has_correct_rfc,
      pt.id                                                AS patient_id,
      COALESCE(pt.full_name, pt.display_name)              AS patient_name,
      sp.amount                                            AS stripe_amount,
      sp.stripe_fee                                        AS stripe_fee,
      sp.paid_at                                           AS stripe_paid_at,
      -- Treat consultations without a linked payment as "pay the doctor"
      -- (they're typically just not refunded). Refunded payments will
      -- have pay_doctor=false unless an operator overrode it.
      COALESCE(sp.pay_doctor, TRUE)                        AS pay_doctor,
      -- Doctor share + retentions all zero out when pay_doctor=false so
      -- totals and net_payment_pending stay accurate without special-
      -- casing downstream. Retentions are applied against the doctor
      -- share — no share, no retention.
      CASE WHEN COALESCE(sp.pay_doctor, TRUE)
           THEN $5::float8 ELSE 0::float8 END              AS doctor_share,
      CASE WHEN COALESCE(sp.pay_doctor, TRUE)
           THEN $6::float8 ELSE 0::float8 END              AS iva_retention_to_apply,
      CASE WHEN COALESCE(sp.pay_doctor, TRUE) THEN
        CASE WHEN COALESCE(d.has_correct_rfc, FALSE)
             THEN $7::float8 ELSE $8::float8 END
        ELSE 0::float8 END                                 AS isr_retention_to_apply,
      (COALESCE(pot.paid_out_cents, 0)::float8 / 100.0)    AS paid_out_amount,
      (COALESCE(pot.iva_applied_cents, 0)::float8 / 100.0) AS iva_retentions_applied,
      (COALESCE(pot.isr_applied_cents, 0)::float8 / 100.0) AS isr_retentions_applied,
      pot.payout_date                                      AS payout_date,
      (pot.consultation_id IS NOT NULL)                    AS is_paid_to_doctor
    FROM consultations c
    LEFT JOIN doctors d  ON d.id = c.doctor_id
    LEFT JOIN patients pt ON pt.id = c.patient_id
    LEFT JOIN stripe_payments sp ON (
      sp.consultation_id = c.id
      OR (sp.consultation_id IS NULL
          AND c.stripe_payment_intent_id IS NOT NULL
          AND sp.stripe_payment_intent_id = c.stripe_payment_intent_id)
    )
    LEFT JOIN payout_totals pot ON pot.consultation_id = c.id
    WHERE c.status = 'completed'
      AND c.completed_at >= $1
      AND c.completed_at <= $2
      AND (c.patient_id IS DISTINCT FROM $3)
      AND (c.doctor_id  IS DISTINCT FROM $4)
    ORDER BY c.completed_at ASC
    """

    params = [
      start_naive,
      end_naive,
      @test_patient_id,
      @test_doctor_id,
      @doctor_share_mxn,
      @iva_rate_pct,
      @isr_rate_with_rfc_pct,
      @isr_rate_without_rfc_pct
    ]

    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, params)
    columns = Enum.map(result.columns, &String.to_atom/1)

    result.rows
    |> Enum.map(fn row -> columns |> Enum.zip(row) |> Map.new() end)
    |> Enum.map(&derive_pending/1)
  end

  # Computes `owed_to_doctor` and `net_payment_pending` in Elixir so
  # we only have to maintain the formula in one place. Rounds money
  # columns to 2 decimals to avoid `1.0500000001`-style display noise.
  defp derive_pending(row) do
    doctor_share = to_float(row.doctor_share)
    paid_out = to_float(row.paid_out_amount)
    iva_to_apply = to_float(row.iva_retention_to_apply)
    isr_to_apply = to_float(row.isr_retention_to_apply)
    iva_applied = to_float(row.iva_retentions_applied)
    isr_applied = to_float(row.isr_retentions_applied)

    owed_to_doctor = doctor_share - paid_out

    net_payment_pending =
      owed_to_doctor -
        (iva_to_apply - iva_applied) -
        (isr_to_apply - isr_applied)

    row
    |> Map.put(:doctor_share, Float.round(doctor_share, 2))
    |> Map.put(:paid_out_amount, Float.round(paid_out, 2))
    |> Map.put(:iva_retention_to_apply, Float.round(iva_to_apply, 2))
    |> Map.put(:isr_retention_to_apply, Float.round(isr_to_apply, 2))
    |> Map.put(:iva_retentions_applied, Float.round(iva_applied, 2))
    |> Map.put(:isr_retentions_applied, Float.round(isr_applied, 2))
    |> Map.put(:owed_to_doctor, Float.round(owed_to_doctor, 2))
    |> Map.put(:net_payment_pending, Float.round(net_payment_pending, 2))
    |> Map.put(:stripe_amount, round_or_nil(row[:stripe_amount]))
    |> Map.put(:stripe_fee, round_or_nil(row[:stripe_fee]))
  end

  # ── Per-doctor aggregation ─────────────────────────────────────

  defp aggregate_by_doctor(consultations) do
    consultations
    |> Enum.group_by(& &1.doctor_id)
    |> Enum.map(fn {doctor_id, rows} ->
      sample = List.first(rows)

      rated = Enum.filter(rows, &is_integer(&1.patient_rating))
      rated_count = length(rated)

      avg_rating =
        if rated_count > 0 do
          sum = Enum.reduce(rated, 0, &(&2 + &1.patient_rating))
          Float.round(sum / rated_count, 2)
        end

      %{
        doctor_id: doctor_id,
        doctor_name: sample.doctor_name || "—",
        doctor_specialty: sample.doctor_specialty,
        has_correct_rfc: sample.has_correct_rfc,
        consultations: length(rows),
        skipped_count: Enum.count(rows, &(&1.pay_doctor == false)),
        paid_to_doctor_count: Enum.count(rows, & &1.is_paid_to_doctor),
        doctor_share: sum_round(rows, :doctor_share),
        paid_out_amount: sum_round(rows, :paid_out_amount),
        iva_retention_to_apply: sum_round(rows, :iva_retention_to_apply),
        isr_retention_to_apply: sum_round(rows, :isr_retention_to_apply),
        iva_retentions_applied: sum_round(rows, :iva_retentions_applied),
        isr_retentions_applied: sum_round(rows, :isr_retentions_applied),
        owed_to_doctor: sum_round(rows, :owed_to_doctor),
        net_payment_pending: sum_round(rows, :net_payment_pending),
        avg_rating: avg_rating,
        rated_count: rated_count
      }
    end)
    |> Enum.sort_by(& &1.net_payment_pending, :desc)
  end

  defp totals(consultations, per_doctor) do
    rated = Enum.filter(consultations, &is_integer(&1.patient_rating))
    rated_count = length(rated)

    avg_rating =
      if rated_count > 0 do
        sum = Enum.reduce(rated, 0, &(&2 + &1.patient_rating))
        Float.round(sum / rated_count, 2)
      end

    %{
      total_consultations: length(consultations),
      paid_to_doctor_count: Enum.count(consultations, & &1.is_paid_to_doctor),
      unique_doctors: length(per_doctor),
      total_doctor_share: sum_round(consultations, :doctor_share),
      total_paid_out: sum_round(consultations, :paid_out_amount),
      total_iva_to_apply: sum_round(consultations, :iva_retention_to_apply),
      total_isr_to_apply: sum_round(consultations, :isr_retention_to_apply),
      total_iva_applied: sum_round(consultations, :iva_retentions_applied),
      total_isr_applied: sum_round(consultations, :isr_retentions_applied),
      total_owed_to_doctor: sum_round(consultations, :owed_to_doctor),
      total_net_payment_pending: sum_round(consultations, :net_payment_pending),
      avg_rating: avg_rating,
      rated_count: rated_count
    }
  end

  defp sum_round(rows, key) do
    rows
    |> Enum.reduce(0.0, fn r, acc -> acc + to_float(Map.get(r, key)) end)
    |> Float.round(2)
  end

  # ── CSV export ─────────────────────────────────────────────────

  @doc """
  Builds a CSV string with three sections: header banner,
  per-consultation detail, and per-doctor summary. Excel + Google
  Sheets both open it natively.
  """
  def to_csv(%{
        consultations: consultations,
        per_doctor: per_doctor,
        period: {s, e},
        totals: t,
        include_settled?: include_settled?
      }) do
    period_label = "#{s} to #{e}"

    consult_header = [
      "Consultation ID",
      "Completed at",
      "Doctor",
      "Specialty",
      "RFC verified",
      "Patient",
      "Type",
      "Duration (min)",
      "Pay doctor?",
      "Doctor share (MXN)",
      "IVA retention to apply",
      "ISR retention to apply",
      "Paid out (MXN)",
      "IVA retentions applied",
      "ISR retentions applied",
      "Owed to doctor (MXN)",
      "Net payment pending (MXN)",
      "Payout date",
      "Paid to doctor?",
      "Rating"
    ]

    consult_rows =
      Enum.map(consultations, fn r ->
        [
          r.consultation_id,
          format_naive(r.completed_at),
          r.doctor_name || "",
          r.doctor_specialty || "",
          yes_no(r.has_correct_rfc),
          r.patient_name || "",
          r.consultation_type || "",
          r.duration_minutes,
          yes_no(r.pay_doctor),
          r.doctor_share,
          r.iva_retention_to_apply,
          r.isr_retention_to_apply,
          r.paid_out_amount,
          r.iva_retentions_applied,
          r.isr_retentions_applied,
          r.owed_to_doctor,
          r.net_payment_pending,
          r.payout_date,
          yes_no(r.is_paid_to_doctor),
          r.patient_rating
        ]
      end)

    doctor_header = [
      "Doctor",
      "Specialty",
      "RFC verified",
      "Consultations",
      "Paid to doctor",
      "Doctor share (MXN)",
      "Paid out (MXN)",
      "ISR to apply",
      "ISR applied",
      "Owed to doctor",
      "Net payment pending",
      "Avg rating",
      "# rated"
    ]

    doctor_rows =
      Enum.map(per_doctor, fn r ->
        [
          r.doctor_name,
          r.doctor_specialty || "",
          yes_no(r.has_correct_rfc),
          r.consultations,
          r.paid_to_doctor_count,
          r.doctor_share,
          r.paid_out_amount,
          r.isr_retention_to_apply,
          r.isr_retentions_applied,
          r.owed_to_doctor,
          r.net_payment_pending,
          r.avg_rating,
          r.rated_count
        ]
      end)

    scope_line =
      if include_settled?,
        do: "All completed consultations (including settled with net pending = 0).",
        else: "Only consultations with net payment pending ≠ 0."

    sections = [
      [
        ["HelloDoctor — Weekly Doctor Payout Report"],
        ["Period", "#{s}", "to", "#{e}"],
        ["Scope", scope_line],
        []
      ],
      [
        ["Consultations — period #{period_label}"],
        consult_header | consult_rows
      ],
      [[]],
      [
        ["Per-doctor summary — period #{period_label}"],
        doctor_header | doctor_rows
      ],
      [[]],
      [
        ["Totals — period #{period_label}"],
        ["Consultations", t.total_consultations],
        ["Paid to doctor (count)", t.paid_to_doctor_count],
        ["Unique doctors", t.unique_doctors],
        ["Doctor share total (MXN)", t.total_doctor_share],
        ["Paid out total (MXN)", t.total_paid_out],
        ["IVA to apply total", t.total_iva_to_apply],
        ["ISR to apply total", t.total_isr_to_apply],
        ["IVA applied total", t.total_iva_applied],
        ["ISR applied total", t.total_isr_applied],
        ["Owed to doctor (MXN)", t.total_owed_to_doctor],
        ["Net payment pending (MXN)", t.total_net_payment_pending],
        ["Average patient rating", t.avg_rating],
        ["# consultations rated", t.rated_count]
      ]
    ]

    sections
    |> Enum.concat()
    |> Enum.map_join("", &encode_row/1)
  end

  defp encode_row(row) when is_list(row) do
    row
    |> Enum.map(&csv_field/1)
    |> Enum.join(",")
    |> Kernel.<>("\r\n")
  end

  defp csv_field(nil), do: ""
  defp csv_field(v) when is_integer(v) or is_float(v), do: to_string(v)

  defp csv_field(%Date{} = d), do: Date.to_iso8601(d)
  defp csv_field(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_string(ndt)

  defp csv_field(v) when is_binary(v) do
    if String.contains?(v, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(v, "\"", "\"\"")}")
    else
      v
    end
  end

  defp csv_field(other), do: csv_field(to_string(other))

  # ── Misc helpers ───────────────────────────────────────────────

  defp format_naive(nil), do: ""
  defp format_naive(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_string(ndt)

  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"
  defp yes_no(_), do: ""

  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(n) when is_float(n), do: n

  defp round_or_nil(nil), do: nil
  defp round_or_nil(v), do: v |> to_float() |> Float.round(2)

  def doctor_share_per_consultation, do: @doctor_share_mxn
end
