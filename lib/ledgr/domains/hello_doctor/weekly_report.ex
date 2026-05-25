defmodule Ledgr.Domains.HelloDoctor.WeeklyReport do
  @moduledoc """
  Weekly consultations & doctor payout report for HelloDoctor.

  Defaults the period to the previous full week (Mon–Sun) in Mexico City time.

  Payout rule (per paid consultation):
    - Doctor receives: `@doctor_share_mxn` (flat, 100 MXN)
    - HelloDoctor keeps the remainder minus Stripe fees.
  """

  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.DoctorPayouts.DoctorPayoutConsultation
  alias Ledgr.Domains.HelloDoctor.Patients.Patient
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment

  @doctor_share_mxn 100.0
  @paid_statuses ~w[paid confirmed]

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

  Returns a map:
    %{
      period: {start_date, end_date},
      consultations: [...],   # one row per attended consultation
      per_doctor:    [...],   # aggregated by doctor
      totals: %{...}
    }
  """
  def generate(start_date, end_date) do
    consultations = list_attended_consultations(start_date, end_date)
    per_doctor = aggregate_by_doctor(consultations)
    totals = totals(consultations, per_doctor)

    %{
      period: {start_date, end_date},
      consultations: consultations,
      per_doctor: per_doctor,
      totals: totals
    }
  end

  # ── Per-consultation query ─────────────────────────────────────

  @doc """
  Returns consultations that are **pending doctor payout** in
  [start_date, end_date], joined with doctor, patient and any linked
  Stripe payment.

  Matches the "Pending payout" filter on the Doctor Payouts page so the
  report becomes the actionable list to pay out from. Excludes:

    * consultations already linked to a `doctor_payouts` row (paid)
    * refunded consultations (`payment_status = "refunded"`)
    * bot test/bypass flows (no Stripe payment AND no consultation amount)

  Joins `stripe_payments` on `consultation_id` first, falling back to
  `stripe_payment_intent_id` — matches the page's behavior so historical
  payments still resolve before `PaymentLinking.backfill_by_payment_intent/0`
  has been re-run.
  """
  def list_attended_consultations(start_date, end_date) do
    start_naive = NaiveDateTime.new!(start_date, ~T[00:00:00])
    end_naive = NaiveDateTime.new!(end_date, ~T[23:59:59])

    query =
      from c in Consultation,
        as: :consultation,
        left_join: d in Doctor,
        on: d.id == c.doctor_id,
        left_join: pt in Patient,
        on: pt.id == c.patient_id,
        left_join: p in StripePayment,
        on:
          (p.consultation_id == c.id or
             (is_nil(p.consultation_id) and
                not is_nil(c.stripe_payment_intent_id) and
                p.stripe_payment_intent_id == c.stripe_payment_intent_id)),
        where: c.status == "completed",
        # Filter on the same billing-date COALESCE as the Doctor Payouts page
        # so the report shows exactly the rows the page lists under Pending.
        where:
          fragment(
            "COALESCE(?, ?, ?, ?) >= ?",
            p.paid_at,
            c.payment_confirmed_at,
            c.completed_at,
            c.assigned_at,
            ^start_naive
          ) and
            fragment(
              "COALESCE(?, ?, ?, ?) <= ?",
              p.paid_at,
              c.payment_confirmed_at,
              c.completed_at,
              c.assigned_at,
              ^end_naive
            ),
        # Only consultations where revenue exists and the doctor is owed.
        where: c.payment_status in ^@paid_statuses,
        # Exclude refunded consultations — match the page's refunded? logic
        # (Stripe full refund, partial refund, or consultation marked refunded).
        where: is_nil(p.status) or p.status != "refunded",
        where: is_nil(p.amount_refunded) or p.amount_refunded == 0.0,
        # Skip bot test/bypass — match the page filter.
        where:
          not is_nil(p.id) or
            (not is_nil(c.payment_amount) and c.payment_amount > 0.0),
        # Pending only — exclude consultations already paid out to a doctor.
        where:
          not exists(
            from dpc in DoctorPayoutConsultation,
              where: dpc.consultation_id == parent_as(:consultation).id
          ),
        order_by: [asc: c.completed_at],
        select: %{
          consultation_id: c.id,
          completed_at: c.completed_at,
          assigned_at: c.assigned_at,
          duration_minutes: c.duration_minutes,
          consultation_type: c.consultation_type,
          payment_status: c.payment_status,
          payment_amount: c.payment_amount,
          patient_rating: c.patient_rating,
          doctor_id: d.id,
          doctor_name: d.name,
          doctor_specialty: d.specialty,
          patient_name: coalesce(pt.full_name, pt.display_name),
          stripe_amount: p.amount,
          stripe_fee: p.stripe_fee,
          stripe_paid_at: p.paid_at
        }

    query
    |> Repo.all()
    |> Enum.map(&annotate_row/1)
  end

  defp annotate_row(row) do
    paid? = row.payment_status in @paid_statuses

    billed = to_float(row.stripe_amount) |> nonzero_or(to_float(row.payment_amount))
    fee = to_float(row.stripe_fee)

    doctor_share = if paid?, do: @doctor_share_mxn, else: 0.0
    hd_gross = if paid?, do: billed - doctor_share, else: 0.0
    hd_net = hd_gross - fee

    Map.merge(row, %{
      paid?: paid?,
      billed: Float.round(billed, 2),
      stripe_fee: Float.round(fee, 2),
      doctor_share: Float.round(doctor_share, 2),
      hd_net: Float.round(hd_net, 2)
    })
  end

  # ── Per-doctor aggregation ─────────────────────────────────────

  defp aggregate_by_doctor(consultations) do
    consultations
    |> Enum.group_by(& &1.doctor_id)
    |> Enum.map(fn {doctor_id, rows} ->
      sample = List.first(rows)
      paid_rows = Enum.filter(rows, & &1.paid?)

      total_billed = Enum.reduce(paid_rows, 0.0, &(&2 + &1.billed))
      total_fees = Enum.reduce(paid_rows, 0.0, &(&2 + &1.stripe_fee))
      doctor_share = Enum.reduce(paid_rows, 0.0, &(&2 + &1.doctor_share))
      hd_net = total_billed - doctor_share - total_fees

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
        consultations: length(rows),
        paid_consultations: length(paid_rows),
        total_billed: Float.round(total_billed, 2),
        stripe_fees: Float.round(total_fees, 2),
        doctor_share: Float.round(doctor_share, 2),
        hd_net: Float.round(hd_net, 2),
        avg_rating: avg_rating,
        rated_count: rated_count
      }
    end)
    |> Enum.sort_by(& &1.doctor_share, :desc)
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
      paid_consultations: Enum.count(consultations, & &1.paid?),
      unique_doctors: length(per_doctor),
      total_billed: sum_round(per_doctor, :total_billed),
      total_doctor_share: sum_round(per_doctor, :doctor_share),
      total_stripe_fees: sum_round(per_doctor, :stripe_fees),
      total_hd_net: sum_round(per_doctor, :hd_net),
      avg_rating: avg_rating,
      rated_count: rated_count
    }
  end

  defp sum_round(rows, key) do
    rows
    |> Enum.reduce(0.0, fn r, acc -> acc + Map.get(r, key, 0.0) end)
    |> Float.round(2)
  end

  # ── CSV export ─────────────────────────────────────────────────

  @doc """
  Builds a CSV string with two sections: per-consultation detail and
  per-doctor summary. Excel and Google Sheets both open this natively.
  """
  def to_csv(%{consultations: consultations, per_doctor: per_doctor, period: {s, e}, totals: t}) do
    period_label = "#{s} to #{e}"

    # Each row carries the period as its first two columns so the data is
    # self-describing — survives sorting, merging, or being pasted into a
    # rolling sheet that combines multiple weeks. Doctors flagged in feedback
    # that they couldn't tell which week a row belonged to once it left the
    # original file.
    consult_header = [
      "Period start",
      "Period end",
      "Consultation ID",
      "Completed at",
      "Doctor",
      "Specialty",
      "Patient",
      "Type",
      "Duration (min)",
      "Payment status",
      "Billed (MXN)",
      "Stripe fee (MXN)",
      "Doctor share (MXN)",
      "HD net (MXN)",
      "Rating"
    ]

    consult_rows =
      Enum.map(consultations, fn r ->
        [
          "#{s}",
          "#{e}",
          r.consultation_id,
          format_naive(r.completed_at),
          r.doctor_name || "",
          r.doctor_specialty || "",
          r.patient_name || "",
          r.consultation_type || "",
          r.duration_minutes,
          r.payment_status || "",
          r.billed,
          r.stripe_fee,
          r.doctor_share,
          r.hd_net,
          r.patient_rating
        ]
      end)

    doctor_header = [
      "Period start",
      "Period end",
      "Doctor",
      "Specialty",
      "Consultations",
      "Paid",
      "Total billed (MXN)",
      "Stripe fees (MXN)",
      "Doctor payout (MXN)",
      "HD net (MXN)",
      "Avg rating",
      "# rated"
    ]

    doctor_rows =
      Enum.map(per_doctor, fn r ->
        [
          "#{s}",
          "#{e}",
          r.doctor_name,
          r.doctor_specialty || "",
          r.consultations,
          r.paid_consultations,
          r.total_billed,
          r.stripe_fees,
          r.doctor_share,
          r.hd_net,
          r.avg_rating,
          r.rated_count
        ]
      end)

    sections = [
      [
        ["HelloDoctor — Weekly Pending Doctor Payouts"],
        ["Period", "#{s}", "to", "#{e}"],
        [
          "Scope",
          "Only consultations pending payout — already-paid and refunded excluded."
        ],
        []
      ],
      [
        ["Pending consultations — period #{period_label}"],
        consult_header | consult_rows
      ],
      [[]],
      [
        ["Per-doctor pending payout summary — period #{period_label}"],
        doctor_header | doctor_rows
      ],
      [[]],
      [
        ["Totals — period #{period_label}"],
        ["Period start", "#{s}"],
        ["Period end", "#{e}"],
        ["Consultations", t.total_consultations],
        ["Paid consultations", t.paid_consultations],
        ["Unique doctors", t.unique_doctors],
        ["Total billed (MXN)", t.total_billed],
        ["Stripe fees (MXN)", t.total_stripe_fees],
        ["Total doctor payout (MXN)", t.total_doctor_share],
        ["HD net (MXN)", t.total_hd_net],
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

  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(n) when is_float(n), do: n

  defp nonzero_or(v, fallback) when v == 0.0, do: fallback
  defp nonzero_or(v, _fallback), do: v

  def doctor_share_per_consultation, do: @doctor_share_mxn
end
