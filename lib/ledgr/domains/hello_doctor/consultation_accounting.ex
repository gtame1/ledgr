defmodule Ledgr.Domains.HelloDoctor.ConsultationAccounting do
  @moduledoc """
  Accounting integration for HelloDoctor consultations.

  When a patient pays for a consultation (via Stripe), this module creates
  the double-entry journal entries:

  1. Revenue recognition:
     DEBIT  1200 Stripe Receivable     $120   (money coming from Stripe)
     CREDIT 4000 Consultation Revenue  $120   (full amount as revenue)

  2. Stripe processing fee:
     DEBIT  6000 Payment Processing    $5     (actual Stripe fee)
     CREDIT 1200 Stripe Receivable     $5     (deducted from receivable)

  3. Doctor payout (tenant-aware share per paid consultation — flat $100 for
     HD-sourced MVP, the doctor's negotiated fee for their own DIRECT patients):
     DEBIT  4000 Consultation Revenue  $share   (reclassify doctor's share)
     CREDIT 2000 Doctor Payable        $share   (owe doctor their share)

  Net result: HelloDoctor keeps (amount − doctor share) commission minus Stripe fees.
  """

  require Logger
  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry
  alias Ledgr.Domains.HelloDoctor
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
  alias Ledgr.Domains.HelloDoctor.DoctorRates
  alias Ledgr.Domains.HelloDoctor.StripeFees

  # Account codes from HelloDoctor domain config
  @stripe_receivable_code "1200"
  @accounts_receivable_code "1100"
  @consultation_revenue_code "4000"
  @payment_processing_code "6000"
  @doctor_payable_code "2000"

  @doc """
  Records a consultation payment as journal entries.

  `consultation` must have patient and doctor preloaded.
  `amount_pesos` is the total payment amount in pesos (float).

  Options:
    :stripe_session_id — used to fetch the actual Stripe fee from the API
    :stripe_fee_cents  — if already known (e.g. from the webhook upsert),
                         use this and skip the extra API round trip
  """
  def record_payment(consultation, amount_pesos, opts \\ []) do
    amount_cents = round(amount_pesos * 100)
    # Tenant-aware doctor share: a doctor's own DIRECT patients (conversation
    # tenant "direct") pay that doctor's negotiated fee; everything else pays
    # the flat share. Mirrors the reports so the GL and the payout report agree
    # (a $200 direct consult reclassifies $200 to Doctor Payable, not $100).
    doctor_payout_cents = DoctorRates.doctor_share_cents(consultation)

    stripe_session_id = opts[:stripe_session_id]

    # Prefer the fee passed in (already fetched at webhook time); fall back to
    # Stripe API; finally fall back to an estimate.
    fee_cents =
      opts[:stripe_fee_cents] ||
        StripeFees.fetch_stripe_fee_cents(stripe_session_id) ||
        StripeFees.estimate_stripe_fee_cents(amount_cents)

    patient_name =
      if consultation.patient do
        consultation.patient.full_name || consultation.patient.display_name || "Patient"
      else
        "Patient"
      end

    doctor_name =
      if consultation.doctor do
        consultation.doctor.name || "Doctor"
      else
        "Unassigned"
      end

    # Look up accounts
    stripe_receivable = Accounting.get_account_by_code!(@stripe_receivable_code)
    consultation_revenue = Accounting.get_account_by_code!(@consultation_revenue_code)
    payment_processing = Accounting.get_account_by_code!(@payment_processing_code)
    doctor_payable = Accounting.get_account_by_code!(@doctor_payable_code)

    entry_attrs = %{
      date: Date.utc_today(),
      entry_type: "consultation_payment",
      reference: "Consultation #{consultation.id}",
      description: "Payment from #{patient_name} — Dr. #{doctor_name}",
      payee: patient_name
    }

    lines = [
      # 1. Revenue recognition: Stripe Receivable <- Consultation Revenue
      %{
        account_id: stripe_receivable.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Stripe payment received for consultation #{consultation.id}"
      },
      %{
        account_id: consultation_revenue.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Consultation revenue — #{patient_name}"
      },
      # 2. Stripe fee
      %{
        account_id: payment_processing.id,
        debit_cents: fee_cents,
        credit_cents: 0,
        description: "Stripe processing fee for consultation #{consultation.id}"
      },
      %{
        account_id: stripe_receivable.id,
        debit_cents: 0,
        credit_cents: fee_cents,
        description: "Stripe fee deducted from receivable"
      },
      # 3. Doctor payout (tenant-aware share): reclassify from revenue to payable
      %{
        account_id: consultation_revenue.id,
        debit_cents: doctor_payout_cents,
        credit_cents: 0,
        description: "Doctor's share — Dr. #{doctor_name}"
      },
      %{
        account_id: doctor_payable.id,
        debit_cents: 0,
        credit_cents: doctor_payout_cents,
        description: "Owed to Dr. #{doctor_name} for consultation #{consultation.id}"
      }
    ]

    case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
      {:ok, entry} ->
        Logger.info(
          "[HelloDoctor] Created journal entry ##{entry.id} for consultation #{consultation.id}: $#{amount_pesos} MXN"
        )

        {:ok, entry}

      {:error, changeset} ->
        Logger.error(
          "[HelloDoctor] Failed to create journal entry for consultation #{consultation.id}: #{inspect(changeset)}"
        )

        {:error, changeset}
    end
  end

  # ── Corporate (employer-paid) consultations ────────────────────

  @doc """
  Records a corporate (employer-paid) consultation as journal entries.

  Corporate consults never touch Stripe — the employer is invoiced on net
  terms at the account's negotiated rate — so `record_payment/2` never runs
  and nothing ever credits Doctor Payable. This posts the equivalent double
  entry so the books balance when the doctor is later paid:

  1. Revenue recognition against a receivable (the employer owes HD):
     DEBIT  1100 Accounts Receivable   $rate
     CREDIT 4000 Consultation Revenue  $rate

  2. Doctor's tenant-aware share reclassified from revenue to payable:
     DEBIT  4000 Consultation Revenue  $share
     CREDIT 2000 Doctor Payable        $share

  Net: HD keeps (rate − share) as corporate margin; 1100 carries the employer
  receivable until they settle the invoice (booked separately as
  `Dr 1010 / Cr 1100`). There is no Stripe fee.

  Idempotent — a consult that already has its `"Corporate consultation <id>"`
  entry is a no-op (`{:ok, :already_posted}`).
  """
  def record_corporate_payment(%Consultation{} = consultation) do
    # Only :doctor / :patient are preloaded for names — NOT :conversation. The
    # conversation row is bot-owned with columns some environments lack; the
    # tenant we need for the doctor share is read via a targeted query instead
    # (see corporate_doctor_cents/1).
    consultation = Repo.preload(consultation, [:doctor, :patient])
    ref = corporate_reference(consultation.id)

    if corporate_entry_exists?(ref) do
      {:ok, :already_posted}
    else
      do_record_corporate_payment(consultation, ref)
    end
  end

  defp do_record_corporate_payment(consultation, ref) do
    revenue_cents = corporate_revenue_cents(consultation)
    doctor_cents = DoctorRates.doctor_share_cents_for_consultation_id(consultation.id)

    if revenue_cents == 0 and doctor_cents == 0 do
      {:ok, :nothing_to_post}
    else
      patient_name = corporate_patient_name(consultation)
      doctor_name = corporate_doctor_name(consultation)

      accounts_receivable = Accounting.get_account_by_code!(@accounts_receivable_code)
      consultation_revenue = Accounting.get_account_by_code!(@consultation_revenue_code)
      doctor_payable = Accounting.get_account_by_code!(@doctor_payable_code)

      entry_attrs = %{
        # Date the revenue when the consult happened (period-correct P&L),
        # falling back to today if there's no completion timestamp.
        date: corporate_entry_date(consultation),
        entry_type: "corporate_consultation",
        reference: ref,
        description: "Corporate consultation — #{patient_name} — Dr. #{doctor_name}",
        payee: patient_name
      }

      # Revenue-recognition legs only make sense when we know the billed rate;
      # skip the zero pair (the entry stays balanced) when it's unknown, but
      # always post the doctor-share reclass so Doctor Payable is credited.
      revenue_lines =
        if revenue_cents > 0 do
          [
            %{
              account_id: accounts_receivable.id,
              debit_cents: revenue_cents,
              credit_cents: 0,
              description: "Corporate receivable for consultation #{consultation.id}"
            },
            %{
              account_id: consultation_revenue.id,
              debit_cents: 0,
              credit_cents: revenue_cents,
              description: "Corporate consultation revenue — #{patient_name}"
            }
          ]
        else
          []
        end

      doctor_lines =
        if doctor_cents > 0 do
          [
            %{
              account_id: consultation_revenue.id,
              debit_cents: doctor_cents,
              credit_cents: 0,
              description: "Doctor's share — Dr. #{doctor_name}"
            },
            %{
              account_id: doctor_payable.id,
              debit_cents: 0,
              credit_cents: doctor_cents,
              description:
                "Owed to Dr. #{doctor_name} for corporate consultation #{consultation.id}"
            }
          ]
        else
          []
        end

      case Accounting.create_journal_entry_with_lines(entry_attrs, revenue_lines ++ doctor_lines) do
        {:ok, entry} ->
          Logger.info(
            "[HelloDoctor] Created corporate journal entry ##{entry.id} for consultation #{consultation.id}: revenue $#{revenue_cents / 100} / doctor $#{doctor_cents / 100} MXN"
          )

          {:ok, entry}

        {:error, changeset} ->
          Logger.error(
            "[HelloDoctor] Failed to create corporate journal entry for consultation #{consultation.id}: #{inspect(changeset)}"
          )

          {:error, changeset}
      end
    end
  end

  @doc """
  Posts the corporate revenue + doctor-payable journal entries for every
  eligible corporate consult that doesn't already have them.

  Eligible = `payment_source = 'corporate'`, collected (`payment_status` in
  paid/confirmed), and a real visit (status not cancelled/consultation_failed).
  (`payment_source = 'test'` bypass rows are corporate-free by construction, so
  no extra test-account filter is needed.)

  Idempotent — safe to re-run; already-posted consults are skipped. Returns
  `%{posted: N, skipped: N, errors: N}`.
  """
  def backfill_corporate_journal_entries do
    consultations =
      from(c in Consultation,
        where:
          c.payment_source == "corporate" and
            c.payment_status in ["paid", "confirmed"] and
            c.status not in ["cancelled", "consultation_failed"]
      )
      |> Repo.all()
      |> Repo.preload([:doctor, :patient])

    result =
      Enum.reduce(consultations, %{posted: 0, skipped: 0, errors: 0}, fn consultation, acc ->
        case record_corporate_payment(consultation) do
          {:ok, %JournalEntry{}} -> %{acc | posted: acc.posted + 1}
          {:ok, :already_posted} -> %{acc | skipped: acc.skipped + 1}
          {:ok, :nothing_to_post} -> %{acc | skipped: acc.skipped + 1}
          _ -> %{acc | errors: acc.errors + 1}
        end
      end)

    Logger.info("[HelloDoctor] Corporate GL backfill complete: #{inspect(result)}")
    {:ok, result}
  end

  defp corporate_reference(consultation_id), do: "Corporate consultation #{consultation_id}"

  defp corporate_entry_exists?(ref) do
    Repo.exists?(from(je in JournalEntry, where: je.reference == ^ref))
  end

  # Revenue to recognize for a corporate consult, in centavos. Prefer the
  # rate the bot stamped on the consultation (`payment_amount`); fall back to
  # the corporate account's negotiated `consultation_rate_mxn` when it's absent.
  defp corporate_revenue_cents(consultation) do
    if is_number(consultation.payment_amount) and consultation.payment_amount > 0 do
      round(consultation.payment_amount * 100)
    else
      corporate_rate_cents(consultation.corporate_account_id)
    end
  end

  defp corporate_rate_cents(account_id) when is_binary(account_id) and account_id != "" do
    # `corporate_accounts` is bot-owned (no Ecto schema) — read the rate raw.
    sql = "SELECT consultation_rate_mxn FROM corporate_accounts WHERE id = $1"

    case Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [account_id]) do
      %{rows: [[rate]]} when is_integer(rate) -> rate * 100
      %{rows: [[rate]]} when is_float(rate) -> round(rate * 100)
      _ -> 0
    end
  end

  defp corporate_rate_cents(_), do: 0

  # Tenant-aware doctor share (centavos) for a corporate consult, without
  # preloading the bot-owned Conversation schema. Reads just the conversation
  # tenant + doctor fee, then applies the same rule as `DoctorRates.doctor_share_mxn()/2`
  # (direct → the doctor's negotiated fee; else the flat share).
  defp corporate_entry_date(consultation) do
    case consultation.completed_at do
      %NaiveDateTime{} = ndt -> HelloDoctor.to_mx_date(ndt)
      _ -> Date.utc_today()
    end
  end

  defp corporate_patient_name(%{patient: %{} = patient}),
    do: patient.full_name || patient.display_name || "Patient"

  defp corporate_patient_name(_), do: "Patient"

  defp corporate_doctor_name(%{doctor: %{} = doctor}), do: doctor.name || "Doctor"
  defp corporate_doctor_name(_), do: "Unassigned"

end
