defmodule Ledgr.Domains.HelloDoctor.DoctorPayouts do
  @moduledoc """
  Doctor payouts — listing every billed consultation with its payout status
  and recording payouts (one or many consultations per payout).

  A payout is the act of HelloDoctor sending money to a doctor for one or
  more consultations. Each payout, in a single transaction:

    * inserts a journal entry recording the cash movement
      (DEBIT 2000 Doctor Payable / CREDIT 1010 Bank-MXN)
    * inserts a row in `doctor_payouts` referencing that journal entry
    * inserts one row in `doctor_payout_consultations` per consultation

  All three writes live in the HelloDoctor repo (the `journal_entries` table
  is per-domain), so they're atomic — failure rolls everything back.
  """

  require Logger
  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.Patients.Patient
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment

  alias Ledgr.Domains.HelloDoctor.DoctorPayouts.{
    DoctorPayout,
    DoctorPayoutConsultation
  }

  @doctor_payable_code "2000"
  @bank_mxn_code "1010"

  # Consultations in any of these `payment_status` values are considered
  # billed and worth listing on the payouts page.
  @payable_statuses ~w[paid confirmed refunded]

  # ── Read: per-consultation list with payout status ──────────────

  @doc """
  Returns a list of billed consultations within the date range, enriched
  with doctor/patient names, computed amounts, and any existing payout info.

  The query is driven by `consultations` (the bot's source of truth for
  whether a consultation is paid/refunded), with `stripe_payments`
  left-joined for billing detail. A consultation appears as soon as the
  bot marks it paid; Stripe fees and exact amounts populate once the
  Stripe webhook lands (or `StripeSync.sync_recent_payments/1` runs).
  Until then the row uses `consultation.payment_amount` and flags
  `:stripe_synced?` as `false`.

  Date range filters on the consultation's billing date, taken as the
  first non-null of `stripe_payments.paid_at`,
  `consultation.payment_confirmed_at`, `consultation.completed_at`, or
  `consultation.assigned_at`.

  ## Options

    * `:doctor_id` — restrict to a single doctor
    * `:status` — one of `:all` (default), `:paid` (has ≥1 payout),
      `:unpaid` (no payouts), `:refunded` (stripe refunded or
      consultation marked refunded)
    * `:sort` — one of `:date` (default), `:doctor`, `:billed`, `:hd_net`
    * `:dir` — `:asc` or `:desc` (defaults: date→desc, doctor→asc, billed→desc, hd_net→desc)
  """
  def list_consultations_with_payouts(start_date, end_date, opts \\ []) do
    share = ConsultationAccounting.doctor_share_mxn()
    start_naive = to_naive_start(start_date)
    end_naive = to_naive_end(end_date)
    doctor_id = opts[:doctor_id]

    base_query =
      from(c in Consultation,
        # Most stripe_payments come in without consultation_id set (the bot's
        # WhatsApp checkout uses static payment links with no metadata). Fall
        # back to matching on stripe_payment_intent_id, which the bot DOES
        # write onto the consultation. PaymentLinking.backfill_by_payment_intent/0
        # promotes these soft matches to hard links on stripe_payments.consultation_id.
        left_join: sp in StripePayment,
        on:
          sp.consultation_id == c.id or
            (is_nil(sp.consultation_id) and
               not is_nil(c.stripe_payment_intent_id) and
               sp.stripe_payment_intent_id == c.stripe_payment_intent_id),
        left_join: d in Doctor,
        on: c.doctor_id == d.id,
        left_join: p in Patient,
        on: c.patient_id == p.id,
        where:
          c.payment_status in ^@payable_statuses and
            # Exclude bot test/bypass flows (pi_test_bypass_*, cs_no_payment_*).
            # Real charges either land in stripe_payments (sp.id non-null) or
            # at least carry an amount on the consultation. Test/bypass rows
            # have NULL or zero amount AND no stripe_payment match.
            (not is_nil(sp.id) or
               (not is_nil(c.payment_amount) and c.payment_amount > 0.0)) and
            fragment(
              "COALESCE(?, ?, ?, ?) >= ?",
              sp.paid_at,
              c.payment_confirmed_at,
              c.completed_at,
              c.assigned_at,
              ^start_naive
            ) and
            fragment(
              "COALESCE(?, ?, ?, ?) <= ?",
              sp.paid_at,
              c.payment_confirmed_at,
              c.completed_at,
              c.assigned_at,
              ^end_naive
            ),
        select: %{
          consultation_id: c.id,
          doctor_id: d.id,
          doctor_name: d.name,
          doctor_specialty: d.specialty,
          patient_full_name: p.full_name,
          patient_display_name: p.display_name,
          stripe_payment_id: sp.id,
          paid_at:
            fragment(
              "COALESCE(?, ?, ?, ?)",
              sp.paid_at,
              c.payment_confirmed_at,
              c.completed_at,
              c.assigned_at
            ),
          stripe_amount: sp.amount,
          consultation_amount: c.payment_amount,
          amount_refunded: sp.amount_refunded,
          stripe_fee: sp.stripe_fee,
          stripe_status: sp.status,
          consultation_status: c.status,
          consultation_payment_status: c.payment_status
        }
      )

    base_query =
      if doctor_id in [nil, "", "all"],
        do: base_query,
        else: from([c, _sp, _d, _p] in base_query, where: c.doctor_id == ^doctor_id)

    rows = Repo.all(base_query)

    consultation_ids = Enum.map(rows, & &1.consultation_id) |> Enum.reject(&is_nil/1)
    payout_index = payout_summary_for(consultation_ids)

    rows
    |> Enum.map(fn row ->
      stripe_synced? = not is_nil(row.stripe_payment_id)

      billed =
        if stripe_synced?,
          do: to_float(row.stripe_amount),
          else: to_float(row.consultation_amount)

      refunded = to_float(row.amount_refunded)
      fee = to_float(row.stripe_fee)
      hd_net = billed - fee - share - refunded
      summary = Map.get(payout_index, row.consultation_id, %{count: 0, last_date: nil})

      refunded? =
        row.stripe_status == "refunded" or refunded > 0 or
          row.consultation_payment_status == "refunded"

      %{
        consultation_id: row.consultation_id,
        doctor_id: row.doctor_id,
        doctor_name: row.doctor_name || "Unassigned",
        doctor_specialty: row.doctor_specialty,
        patient_name: row.patient_full_name || row.patient_display_name || "Unknown",
        paid_at: row.paid_at,
        paid_date: paid_date(row.paid_at),
        amount: Float.round(billed, 2),
        amount_refunded: Float.round(refunded, 2),
        stripe_fee: Float.round(fee, 2),
        stripe_status: row.stripe_status || row.consultation_payment_status,
        consultation_status: row.consultation_status,
        stripe_synced?: stripe_synced?,
        refunded?: refunded?,
        doctor_share: Float.round(share, 2),
        hd_net: Float.round(hd_net, 2),
        payout_count: summary.count,
        last_payout_date: summary.last_date
      }
    end)
    |> apply_status_filter(opts[:status])
    |> apply_sort(opts[:sort], opts[:dir])
  end

  defp apply_status_filter(rows, status) when status in [nil, :all, "all", ""], do: rows

  # `pending` — the actionable list: no payout yet AND not refunded.
  # This is the default view; "paid" and "refunded" are filtered out so
  # users see only what still needs to be processed.
  defp apply_status_filter(rows, status) when status in [:pending, "pending"] do
    Enum.filter(rows, &(&1.payout_count == 0 and not &1.refunded?))
  end

  defp apply_status_filter(rows, status) when status in [:paid, "paid"] do
    Enum.filter(rows, &(&1.payout_count > 0))
  end

  defp apply_status_filter(rows, status) when status in [:unpaid, "unpaid"] do
    Enum.filter(rows, &(&1.payout_count == 0))
  end

  defp apply_status_filter(rows, status) when status in [:refunded, "refunded"] do
    Enum.filter(rows, & &1.refunded?)
  end

  defp apply_status_filter(rows, _), do: rows

  defp apply_sort(rows, sort, dir) do
    sort = normalize_sort(sort)
    dir = normalize_dir(dir, sort)
    key_fn = sort_key(sort)
    sorted = Enum.sort_by(rows, key_fn, sort_comparer(dir))
    sorted
  end

  defp normalize_sort(s) when s in [nil, "", :date, "date"], do: :date
  defp normalize_sort(s) when s in [:doctor, "doctor"], do: :doctor
  defp normalize_sort(s) when s in [:billed, "billed"], do: :billed
  defp normalize_sort(s) when s in [:hd_net, "hd_net"], do: :hd_net
  defp normalize_sort(_), do: :date

  defp normalize_dir(d, _) when d in [:asc, "asc"], do: :asc
  defp normalize_dir(d, _) when d in [:desc, "desc"], do: :desc
  # Default direction per column: date/billed/hd_net = desc, doctor = asc.
  defp normalize_dir(_, :doctor), do: :asc
  defp normalize_dir(_, _), do: :desc

  defp sort_key(:doctor), do: & &1.doctor_name
  defp sort_key(:billed), do: & &1.amount
  defp sort_key(:hd_net), do: & &1.hd_net
  defp sort_key(:date), do: &(&1.paid_at || ~N[1970-01-01 00:00:00])

  defp sort_comparer(:asc), do: &<=/2
  defp sort_comparer(:desc), do: &>=/2

  @doc """
  Aggregates a list of consultation rows (as returned by
  `list_consultations_with_payouts/2`) into top-level totals for the KPI cards.
  """
  def summarize(rows) do
    rows
    |> Enum.reduce(
      %{
        total_billed: 0.0,
        total_refunded: 0.0,
        total_stripe_fees: 0.0,
        total_doctor_share: 0.0,
        total_hd_net: 0.0,
        total_paid_out: 0,
        total_unpaid: 0,
        count: 0
      },
      fn r, acc ->
        %{
          total_billed: acc.total_billed + r.amount,
          total_refunded: acc.total_refunded + r.amount_refunded,
          total_stripe_fees: acc.total_stripe_fees + r.stripe_fee,
          total_doctor_share: acc.total_doctor_share + r.doctor_share,
          total_hd_net: acc.total_hd_net + r.hd_net,
          total_paid_out: acc.total_paid_out + if(r.payout_count > 0, do: 1, else: 0),
          total_unpaid: acc.total_unpaid + if(r.payout_count == 0, do: 1, else: 0),
          count: acc.count + 1
        }
      end
    )
    |> then(fn s ->
      %{
        s
        | total_billed: Float.round(s.total_billed, 2),
          total_refunded: Float.round(s.total_refunded, 2),
          total_stripe_fees: Float.round(s.total_stripe_fees, 2),
          total_doctor_share: Float.round(s.total_doctor_share, 2),
          total_hd_net: Float.round(s.total_hd_net, 2)
      }
    end)
  end

  defp payout_summary_for([]), do: %{}

  defp payout_summary_for(consultation_ids) do
    from(j in DoctorPayoutConsultation,
      join: p in DoctorPayout,
      on: p.id == j.doctor_payout_id,
      where: j.consultation_id in ^consultation_ids,
      group_by: j.consultation_id,
      select: {j.consultation_id, count(j.id), max(p.payout_date)}
    )
    |> Repo.all()
    |> Map.new(fn {cid, n, max_date} -> {cid, %{count: n, last_date: max_date}} end)
  end

  # ── Write: record a payout for one or more consultations ────────

  @doc """
  Records a payout to a doctor for one or more consultations.

  `attrs` must include:
    * `:doctor_id` (string)
    * `:consultation_ids` (list of strings, at least one)
    * `:payout_date` (Date)
    * `:amount_cents` (integer, > 0 — the total transferred to the doctor)
    * `:payment_method` (one of `DoctorPayout.payment_methods/0`)

  Optional:
    * `:reference` (string)
    * `:notes` (string)

  Creates: one journal entry (DEBIT 2000 / CREDIT 1010), one doctor_payouts
  row, N doctor_payout_consultations rows. Returns `{:ok, payout}` on
  success; the payout has `:payout_consultations` preloaded.
  """
  def create_payout(attrs) do
    with {:ok, doctor} <- fetch_doctor(attrs),
         {:ok, consultation_ids} <- fetch_consultation_ids(attrs),
         :ok <- validate_consultations_belong_to_doctor(consultation_ids, doctor.id),
         {:ok, payout_date} <- fetch_date(attrs),
         {:ok, amount_cents} <- fetch_amount_cents(attrs),
         {:ok, payment_method} <- fetch_payment_method(attrs) do
      transaction_result =
        Repo.transaction(fn ->
          # $0 payouts represent a "processed" outcome with no cash movement
          # (e.g. refunded consultation the doctor isn't owed for). Skip the
          # journal entry — there's nothing to record.
          je_result =
            if amount_cents == 0,
              do: {:ok, nil},
              else:
                create_journal_entry(
                  doctor,
                  consultation_ids,
                  payout_date,
                  amount_cents,
                  attrs
                )

          with {:ok, je} <- je_result,
               {:ok, payout} <-
                 insert_payout_row(
                   doctor.id,
                   payout_date,
                   amount_cents,
                   payment_method,
                   attrs[:reference],
                   attrs[:notes],
                   je && je.id
                 ),
               :ok <- insert_payout_joins(payout.id, consultation_ids) do
            Repo.preload(payout, :payout_consultations)
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      case transaction_result do
        {:ok, payout} -> {:ok, payout}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fetch_doctor(%{doctor_id: id}) when is_binary(id) and id != "" do
    case Repo.get(Doctor, id) do
      nil -> {:error, "unknown doctor_id"}
      doctor -> {:ok, doctor}
    end
  end

  defp fetch_doctor(_), do: {:error, "doctor_id is required"}

  defp fetch_consultation_ids(%{consultation_ids: ids}) when is_list(ids) and ids != [] do
    cleaned = ids |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

    if cleaned == [], do: {:error, "at least one consultation is required"}, else: {:ok, cleaned}
  end

  defp fetch_consultation_ids(_), do: {:error, "consultation_ids is required"}

  defp validate_consultations_belong_to_doctor(ids, doctor_id) do
    bad =
      from(c in Consultation,
        where: c.id in ^ids and (c.doctor_id != ^doctor_id or is_nil(c.doctor_id)),
        select: c.id
      )
      |> Repo.all()

    case bad do
      [] ->
        :ok

      _ ->
        {:error,
         "consultations don't belong to doctor #{doctor_id}: #{Enum.join(bad, ", ")}"}
    end
  end

  defp fetch_date(%{payout_date: %Date{} = d}), do: {:ok, d}

  defp fetch_date(%{payout_date: d}) when is_binary(d) do
    case Date.from_iso8601(d) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, "invalid payout_date"}
    end
  end

  defp fetch_date(_), do: {:error, "payout_date is required"}

  # Amounts >= 0 are accepted. Zero means "processed, no cash movement".
  defp fetch_amount_cents(%{amount_cents: n}) when is_integer(n) and n >= 0, do: {:ok, n}

  defp fetch_amount_cents(%{amount: a}) when is_binary(a) do
    case Float.parse(String.trim(a)) do
      {pesos, ""} when pesos >= 0 -> {:ok, round(pesos * 100)}
      _ -> {:error, "invalid amount"}
    end
  end

  defp fetch_amount_cents(%{amount: a}) when is_float(a) and a >= 0, do: {:ok, round(a * 100)}
  defp fetch_amount_cents(%{amount: a}) when is_integer(a) and a >= 0, do: {:ok, a * 100}
  defp fetch_amount_cents(_), do: {:error, "amount is required and must be >= 0"}

  defp fetch_payment_method(%{payment_method: m}) when is_binary(m) do
    if m in DoctorPayout.payment_methods(),
      do: {:ok, m},
      else: {:error, "invalid payment_method"}
  end

  defp fetch_payment_method(_), do: {:ok, "bank_transfer"}

  defp create_journal_entry(doctor, consultation_ids, payout_date, amount_cents, attrs) do
    doctor_payable = Accounting.get_account_by_code!(@doctor_payable_code)
    bank_mxn = Accounting.get_account_by_code!(@bank_mxn_code)

    description =
      attrs[:notes] || attrs[:reference] ||
        "Payout to #{doctor.name} — #{length(consultation_ids)} consultation(s)"

    entry_attrs = %{
      date: payout_date,
      entry_type: "doctor_payout",
      reference: "DoctorPayout-#{doctor.id}-#{Date.to_iso8601(payout_date)}",
      description: description,
      payee: doctor.name || "Doctor ##{doctor.id}"
    }

    lines = [
      %{
        account_id: doctor_payable.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Clearing doctor payable — #{doctor.name}"
      },
      %{
        account_id: bank_mxn.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Bank transfer to #{doctor.name}"
      }
    ]

    case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
      {:ok, entry} ->
        {:ok, entry}

      {:error, changeset} ->
        Logger.error(
          "[HelloDoctor] Failed to create journal entry for doctor payout: #{inspect(changeset)}"
        )

        {:error, "failed to record journal entry"}
    end
  end

  defp insert_payout_row(
         doctor_id,
         payout_date,
         amount_cents,
         payment_method,
         reference,
         notes,
         journal_entry_id
       ) do
    %DoctorPayout{}
    |> DoctorPayout.changeset(%{
      doctor_id: doctor_id,
      payout_date: payout_date,
      amount_cents: amount_cents,
      payment_method: payment_method,
      reference: reference,
      notes: notes,
      journal_entry_id: journal_entry_id
    })
    |> Repo.insert()
  end

  defp insert_payout_joins(payout_id, consultation_ids) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(consultation_ids, fn cid ->
        %{
          doctor_payout_id: payout_id,
          consultation_id: cid,
          inserted_at: now,
          updated_at: now
        }
      end)

    case Repo.insert_all(DoctorPayoutConsultation, rows) do
      {n, _} when n == length(rows) -> :ok
      _ -> {:error, "failed to link consultations"}
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp to_float(nil), do: 0.0
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(n) when is_float(n), do: n
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)

  defp paid_date(nil), do: nil
  defp paid_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)

  defp to_naive_start(%Date{} = d), do: NaiveDateTime.new!(d, ~T[00:00:00])
  defp to_naive_end(%Date{} = d), do: NaiveDateTime.new!(d, ~T[23:59:59])
end
