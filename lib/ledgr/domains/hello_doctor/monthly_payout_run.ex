defmodule Ledgr.Domains.HelloDoctor.MonthlyPayoutRun do
  @moduledoc """
  Bulk "mark a month as paid" for the doctor-payout report.

  Reuses `MonthlyReport.list_consultations/2` as the single source of truth for
  who is owed, then — grouped by doctor — records one payout per doctor covering
  every still-owed consultation, withholding ISR exactly as the report shows.

  Two phases per doctor, so the general ledger stays meaningful:

    1. **Comp accruals.** Free / comped consults (`hd_subsidy > 0` — experiment
       first-consults, `cs_no_payment_*`) collected $0, so nothing ever credited
       Doctor Payable (2000) for them. Before paying, post the missing accrual
       `Dr 6050 Marketing & Advertising / Cr 2000 Doctor Payable` for the
       doctor's share (the same manual entry ops already posts by hand).
       Idempotent — skips any consult that already has its accrual JE.

    2. **Payout.** `DoctorPayouts.create_payout/1` for the doctor's whole owed
       set: cash = Σ net_payment_pending (share − ISR), `isr_retention_cents` =
       Σ ISR to apply. This writes the payout row + one join per consultation
       (which is what marks each consultation "paid") + the cash JE
       (Dr 2000 / Cr 1010 / Cr 2200).

  The set to pay is `pay_to_doc AND NOT is_paid_to_doctor`, so re-running is
  idempotent: already-paid consults are excluded by the join filter and
  already-accrued comps by their reference marker.

  Corporate consults (`payment_source = "corporate"`) get the same treatment,
  in a third phase. Like comps they have no Stripe payment JE, but their offset
  is employer *revenue*, not a marketing cost — so before paying we post
  `ConsultationAccounting.record_corporate_payment/1`
  (`Dr 1100 AR / Cr 4000 Revenue` + `Dr 4000 / Cr 2000 Doctor Payable`). Also
  idempotent — a consult that already has its corporate entry is skipped.
  """

  require Logger
  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry
  alias Ledgr.Domains.HelloDoctor
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
  alias Ledgr.Domains.HelloDoctor.DoctorPayouts
  alias Ledgr.Domains.HelloDoctor.MonthlyReport

  @doctor_payable_code "2000"
  @marketing_code "6050"

  # ── Plan (read-only preview) ────────────────────────────────────

  @doc """
  Builds the payout plan for the period WITHOUT writing anything. Returns:

      %{
        period: {start_date, end_date},
        doctors: [%{doctor_id, doctor_name, has_correct_rfc, count,
                    gross_share, isr, net_cash, comp_count, comp_accrual,
                    corporate_count, consultation_ids, rows}],
        totals: %{doctors, consultations, gross_share, isr, net_cash,
                  comp_count, comp_accrual, corporate_count}
      }

  Doctors are sorted by net cash descending.
  """
  def plan(start_date, end_date) do
    owed =
      start_date
      |> MonthlyReport.list_consultations(end_date)
      |> Enum.filter(&(&1.pay_to_doc == true and &1.is_paid_to_doctor == false))

    doctors =
      owed
      |> Enum.group_by(& &1.doctor_id)
      |> Enum.map(fn {doctor_id, rows} -> doctor_plan(doctor_id, rows) end)
      |> Enum.sort_by(& &1.net_cash, :desc)

    %{period: {start_date, end_date}, doctors: doctors, totals: totals(doctors)}
  end

  defp doctor_plan(doctor_id, rows) do
    sample = List.first(rows)
    comp_rows = Enum.filter(rows, &(to_f(&1.hd_subsidy) > 0.0))
    corporate_rows = Enum.filter(rows, &(&1.payment_source == "corporate"))

    %{
      doctor_id: doctor_id,
      doctor_name: sample.doctor_name || "—",
      has_correct_rfc: sample.has_correct_rfc,
      count: length(rows),
      gross_share: sum(rows, :doctor_share),
      isr: sum(rows, :isr_retention_to_apply),
      net_cash: sum(rows, :net_payment_pending),
      comp_count: length(comp_rows),
      comp_accrual: sum(comp_rows, :doctor_share),
      corporate_count: length(corporate_rows),
      # `stripe_amount` carries the billed rate for corporate rows (via the
      # report's payment_amount fallback); nil coerces to 0 in `sum/2`.
      corporate_revenue: sum(corporate_rows, :stripe_amount),
      consultation_ids: Enum.map(rows, & &1.consultation_id),
      rows: rows
    }
  end

  defp totals(doctors) do
    %{
      doctors: length(doctors),
      consultations: sum_field(doctors, :count),
      gross_share: sum_field(doctors, :gross_share),
      isr: sum_field(doctors, :isr),
      net_cash: sum_field(doctors, :net_cash),
      comp_count: sum_field(doctors, :comp_count),
      comp_accrual: sum_field(doctors, :comp_accrual),
      corporate_count: sum_field(doctors, :corporate_count),
      corporate_revenue: sum_field(doctors, :corporate_revenue)
    }
  end

  # ── Execute (writes) ────────────────────────────────────────────

  @doc """
  Records payouts for every owed doctor in the period. `payout_date` is a
  `Date`. Returns a summary map:

      %{doctors_paid, doctors_failed, consultations_paid, accruals_posted,
        corporate_posted, total_cash, total_isr, failures: [{doctor_name, reason}]}

  Each doctor is processed independently — a failure for one doctor doesn't
  abort the others. Safe to re-run: already-paid consults and already-accrued
  comps are skipped.
  """
  def execute(start_date, end_date, %Date{} = payout_date, opts \\ []) do
    period_label = Keyword.get(opts, :period_label, "#{start_date} to #{end_date}")
    plan = plan(start_date, end_date)

    Enum.reduce(
      plan.doctors,
      %{
        doctors_paid: 0,
        doctors_failed: 0,
        consultations_paid: 0,
        accruals_posted: 0,
        corporate_posted: 0,
        total_cash: 0.0,
        total_isr: 0.0,
        failures: []
      },
      fn d, acc ->
        # Post the missing offset JEs BEFORE the payout debits Doctor Payable:
        # comps accrue `Dr 6050 / Cr 2000`, corporate consults recognize
        # `Dr 1100 / Cr 4000` + `Dr 4000 / Cr 2000`. Both idempotent.
        accruals = post_comp_accruals(d, payout_date)
        corporate = post_corporate_revenue(d)

        case record_payout(d, payout_date, period_label) do
          {:ok, _payout} ->
            %{
              acc
              | doctors_paid: acc.doctors_paid + 1,
                consultations_paid: acc.consultations_paid + d.count,
                accruals_posted: acc.accruals_posted + accruals,
                corporate_posted: acc.corporate_posted + corporate,
                total_cash: acc.total_cash + d.net_cash,
                total_isr: acc.total_isr + d.isr
            }

          {:error, reason} ->
            Logger.error(
              "[HelloDoctor] Bulk payout failed for doctor #{d.doctor_id} (#{d.doctor_name}): #{inspect(reason)}"
            )

            %{
              acc
              | doctors_failed: acc.doctors_failed + 1,
                accruals_posted: acc.accruals_posted + accruals,
                corporate_posted: acc.corporate_posted + corporate,
                failures: [{d.doctor_name, reason} | acc.failures]
            }
        end
      end
    )
    |> then(fn s ->
      %{
        s
        | total_cash: Float.round(s.total_cash, 2),
          total_isr: Float.round(s.total_isr, 2),
          failures: Enum.reverse(s.failures)
      }
    end)
  end

  defp record_payout(d, payout_date, period_label) do
    DoctorPayouts.create_payout(%{
      doctor_id: d.doctor_id,
      consultation_ids: d.consultation_ids,
      payout_date: payout_date,
      amount_cents: to_cents(d.net_cash),
      isr_retention_cents: to_cents(d.isr),
      iva_retention_cents: 0,
      payment_method: "bank_transfer",
      reference: "Monthly payout — #{period_label}",
      notes: "Bulk monthly payout (#{period_label}) — #{d.count} consultation(s)"
    })
  end

  # Posts the missing `Dr 6050 / Cr 2000` accrual for each comped consult that
  # doesn't already have one. Returns the count actually posted.
  defp post_comp_accruals(d, payout_date) do
    d.rows
    |> Enum.filter(&(to_f(&1.hd_subsidy) > 0.0))
    |> Enum.reduce(0, fn row, posted ->
      ref = accrual_reference(row.consultation_id)

      cond do
        accrual_exists?(ref) ->
          posted

        true ->
          case post_accrual(row, d, payout_date, ref) do
            {:ok, _} ->
              posted + 1

            {:error, reason} ->
              Logger.error(
                "[HelloDoctor] Comp accrual failed for consultation #{row.consultation_id}: #{inspect(reason)}"
              )

              posted
          end
      end
    end)
  end

  # Posts the corporate revenue + doctor-payable JE for each corporate consult
  # (`payment_source == "corporate"`) that doesn't already have one, via
  # `ConsultationAccounting.record_corporate_payment/1`. Returns the count of
  # entries newly posted this run (already-posted consults don't count).
  defp post_corporate_revenue(d) do
    d.rows
    |> Enum.filter(&(&1.payment_source == "corporate"))
    |> Enum.reduce(0, fn row, posted ->
      case Repo.get(Consultation, row.consultation_id) do
        nil ->
          posted

        consultation ->
          case ConsultationAccounting.record_corporate_payment(consultation) do
            {:ok, %JournalEntry{}} ->
              posted + 1

            {:ok, _skipped} ->
              posted

            {:error, reason} ->
              Logger.error(
                "[HelloDoctor] Corporate revenue JE failed for consultation #{row.consultation_id}: #{inspect(reason)}"
              )

              posted
          end
      end
    end)
  end

  defp accrual_reference(consultation_id), do: "Comp accrual — consultation #{consultation_id}"

  defp accrual_exists?(ref) do
    Repo.exists?(from(je in Accounting.JournalEntry, where: je.reference == ^ref))
  end

  defp post_accrual(row, d, payout_date, ref) do
    share_cents = to_cents(row.doctor_share)
    marketing = Accounting.get_account_by_code!(@marketing_code)
    doctor_payable = Accounting.get_account_by_code!(@doctor_payable_code)

    # Date the expense when the consult happened (period-correct P&L), falling
    # back to the payout date if there's no completion timestamp.
    date =
      case row.completed_at do
        %NaiveDateTime{} = ndt -> HelloDoctor.to_mx_date(ndt)
        _ -> payout_date
      end

    entry_attrs = %{
      date: date,
      entry_type: "marketing_cost",
      reference: ref,
      description: "Comped consultation — Dr #{d.doctor_name}",
      payee: d.doctor_name
    }

    lines = [
      %{
        account_id: marketing.id,
        debit_cents: share_cents,
        credit_cents: 0,
        description: "Comped consultation (doctor's share) — Dr #{d.doctor_name}"
      },
      %{
        account_id: doctor_payable.id,
        debit_cents: 0,
        credit_cents: share_cents,
        description: "Owed to Dr #{d.doctor_name} for comped consultation #{row.consultation_id}"
      }
    ]

    Accounting.create_journal_entry_with_lines(entry_attrs, lines)
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp sum(rows, key),
    do: rows |> Enum.reduce(0.0, fn r, acc -> acc + to_f(Map.get(r, key)) end) |> Float.round(2)

  defp sum_field(maps, key),
    do: maps |> Enum.reduce(0.0, fn m, acc -> acc + to_f(Map.get(m, key)) end) |> Float.round(2)

  defp to_cents(v), do: round(to_f(v) * 100)

  defp to_f(nil), do: 0.0
  defp to_f(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_f(n) when is_integer(n), do: n * 1.0
  defp to_f(n) when is_float(n), do: n
end
