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
  alias Ledgr.Domains.HelloDoctor.ConsultationPayoutDecisions
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.Patients.Patient
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment

  alias Ledgr.Domains.HelloDoctor.DoctorPayouts.{
    DoctorPayout,
    DoctorPayoutConsultation
  }

  @doctor_payable_code "2000"
  @bank_mxn_code "1010"
  # ISR / IVA retentions credited here when a payout withholds tax.
  @taxes_payable_code "2200"

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
    end_exclusive = to_naive_end_exclusive(end_date)
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
        # Exclude bot test/bypass flows (pi_test_bypass_*, cs_no_payment_*).
        # Real charges either land in stripe_payments (sp.id non-null) or
        # at least carry an amount on the consultation. Test/bypass rows
        # have NULL or zero amount AND no stripe_payment match.
        # `>= 0` lets through 100% discount consultations (the bot
        # writes them with payment_amount=0 + cs_no_payment_*
        # stripe_payment_intent_id; no stripe_payments row exists).
        # `not is_nil` still excludes bot test/bypass flows that
        # have NULL amount.
        where:
          c.payment_status in ^@payable_statuses and
            (not is_nil(sp.id) or
               (not is_nil(c.payment_amount) and c.payment_amount >= 0.0)) and
            fragment(
              "COALESCE(?, ?, ?, ?) >= ?",
              sp.paid_at,
              c.payment_confirmed_at,
              c.completed_at,
              c.assigned_at,
              ^start_naive
            ) and
            fragment(
              "COALESCE(?, ?, ?, ?) < ?",
              sp.paid_at,
              c.payment_confirmed_at,
              c.completed_at,
              c.assigned_at,
              ^end_exclusive
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
          consultation_payment_status: c.payment_status,
          # ADR-046: drives payable/discount/corporate disambiguation.
          payment_source: c.payment_source,
          corporate_account_id: c.corporate_account_id
        }
      )

    base_query =
      if doctor_id in [nil, "", "all"],
        do: base_query,
        else: from([c, _sp, _d, _p] in base_query, where: c.doctor_id == ^doctor_id)

    rows = Repo.all(base_query)

    consultation_ids = Enum.map(rows, & &1.consultation_id) |> Enum.reject(&is_nil/1)
    payout_index = payout_summary_for(consultation_ids)
    pay_doctor_index = ConsultationPayoutDecisions.pay_doctor_map(consultation_ids)

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

      summary =
        Map.get(payout_index, row.consultation_id, %{
          count: 0,
          last_date: nil,
          last_payout_id: nil
        })

      refunded? =
        row.stripe_status == "refunded" or refunded > 0 or
          row.consultation_payment_status == "refunded"

      # `pay_doctor?` is the source of truth for whether the doctor is
      # owed for this consultation. Defaults to true when the
      # consultation has no entry in consultation_payout_decisions
      # (the "no override" case).
      pay_doctor? = Map.get(pay_doctor_index, row.consultation_id, true)

      # ADR-046: payment_source is the authoritative signal.
      #   "stripe"    — normal flow (patient paid Stripe)
      #   "corporate" — employer-paid (no Stripe row; doctor IS payable)
      #   "test"      — /prueba bypass (not payable; filtered by caller)
      payment_source = row.payment_source || "stripe"

      corporate_consultation? = payment_source == "corporate"

      # A 100% discount consultation — bot-tagged with `cs_no_payment_*`
      # on consultations.stripe_payment_intent_id and no Stripe charge.
      # We still owe the doctor $100, but the GL has nothing in Doctor
      # Payable yet — operator must post a manual `Dr 6050 / Cr 2000`
      # before recording the payout so the books balance. The
      # payment_source=='stripe' guard keeps corporate consultations
      # (also stripe-less with billed=0) from getting this badge.
      discount_consultation? =
        payment_source == "stripe" and not stripe_synced? and billed == 0.0

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
        pay_doctor?: pay_doctor?,
        payment_source: payment_source,
        corporate_account_id: row.corporate_account_id,
        corporate_consultation?: corporate_consultation?,
        discount_consultation?: discount_consultation?,
        doctor_share: Float.round(if(pay_doctor?, do: share, else: 0.0), 2),
        hd_net: Float.round(hd_net, 2),
        payout_count: summary.count,
        last_payout_date: summary.last_date,
        last_payout_id: summary[:last_payout_id]
      }
    end)
    # ADR-046: /prueba test rows are never doctor-payable — hide them
    # from every status filter.
    |> Enum.reject(&(&1.payment_source == "test"))
    |> apply_status_filter(opts[:status])
    |> apply_sort(opts[:sort], opts[:dir])
  end

  defp apply_status_filter(rows, status) when status in [nil, :all, "all", ""], do: rows

  # `pending` — the actionable list: no payout yet AND we still owe
  # the doctor (pay_doctor flag). A refunded consultation with the
  # "Still pay doctor" override stays pending; a refunded one without
  # it drops out. This is the default view; "paid" and "refunded" are
  # filtered out so users see only what still needs processing.
  defp apply_status_filter(rows, status) when status in [:pending, "pending"] do
    Enum.filter(rows, &(&1.payout_count == 0 and &1.pay_doctor?))
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

  # NOTE: raw `>=`/`<=` term ordering on NaiveDateTime structs compares
  # fields in alphabetical key order (day before month) — sorts May 29
  # *above* June 10. Use `{dir, NaiveDateTime}` for date columns so the
  # comparator dispatches through `NaiveDateTime.compare/2`. Numeric and
  # string columns are fine with the term comparators.
  defp apply_sort(rows, sort, dir) do
    sort = normalize_sort(sort)
    dir = normalize_dir(dir, sort)

    case sort do
      :date ->
        Enum.sort_by(rows, &(&1.paid_at || ~N[1970-01-01 00:00:00]), {dir, NaiveDateTime})

      :doctor ->
        Enum.sort_by(rows, & &1.doctor_name, dir)

      :billed ->
        Enum.sort_by(rows, & &1.amount, dir)

      :hd_net ->
        Enum.sort_by(rows, & &1.hd_net, dir)
    end
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

  @doc """
  Per-consultation payout summary for a single consultation:
  `%{count, last_date, last_payout_id}` (count 0 if never paid). Lets the
  consultation detail page show paid-status by reading the existing
  payout/join tables — no denormalization onto `consultation_payouts`.
  """
  def payout_summary_for_consultation(consultation_id) when is_binary(consultation_id) do
    payout_summary_for([consultation_id])
    |> Map.get(consultation_id, %{count: 0, last_date: nil, last_payout_id: nil})
  end

  defp payout_summary_for([]), do: %{}

  defp payout_summary_for(consultation_ids) do
    # For each consultation, we want the count of payouts, the latest
    # payout_date, AND the id of the most recent payout (so the "Paid"
    # badge on the listing page can link to the edit form). We do this in
    # one round trip with DISTINCT ON ordered by payout_date desc.
    counts =
      from(j in DoctorPayoutConsultation,
        join: p in DoctorPayout,
        on: p.id == j.doctor_payout_id,
        where: j.consultation_id in ^consultation_ids,
        group_by: j.consultation_id,
        select: {j.consultation_id, count(j.id), max(p.payout_date)}
      )
      |> Repo.all()
      |> Map.new(fn {cid, n, max_date} -> {cid, %{count: n, last_date: max_date}} end)

    last_payouts =
      from(j in DoctorPayoutConsultation,
        join: p in DoctorPayout,
        on: p.id == j.doctor_payout_id,
        where: j.consultation_id in ^consultation_ids,
        distinct: j.consultation_id,
        order_by: [asc: j.consultation_id, desc: p.payout_date, desc: p.id],
        select: {j.consultation_id, p.id}
      )
      |> Repo.all()
      |> Map.new()

    Map.new(counts, fn {cid, summary} ->
      {cid, Map.put(summary, :last_payout_id, Map.get(last_payouts, cid))}
    end)
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
         {:ok, iva_cents} <- fetch_retention_cents(attrs, :iva),
         {:ok, isr_cents} <- fetch_retention_cents(attrs, :isr),
         {:ok, payment_method} <- fetch_payment_method(attrs) do
      transaction_result =
        Repo.transaction(fn ->
          # A JE is only worth creating when there's actually money moving
          # somewhere — to the bank, or being retained for SAT. All zero
          # → "processed without any cash movement" → skip the JE.
          je_result =
            if amount_cents == 0 and iva_cents == 0 and isr_cents == 0,
              do: {:ok, nil},
              else:
                create_journal_entry(
                  doctor,
                  consultation_ids,
                  payout_date,
                  amount_cents,
                  iva_cents,
                  isr_cents,
                  attrs
                )

          with {:ok, je} <- je_result,
               {:ok, payout} <-
                 insert_payout_row(
                   doctor.id,
                   payout_date,
                   amount_cents,
                   iva_cents,
                   isr_cents,
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

  @doc "Fetches a payout with its consultation join rows preloaded."
  def get_payout!(id) do
    DoctorPayout
    |> Repo.get!(id)
    |> Repo.preload(:payout_consultations)
  end

  @doc """
  Updates a payout. Same accepted fields as `create_payout/1` except
  `:doctor_id` — that's locked to the existing payout's doctor.

  Performs the edit atomically:

    * Recomputes the journal entry. Old/new amount-zero combinations
      are handled (create, update, delete, or no-op).
    * Replaces the consultation joins with the new set.
    * Updates the payout row's amount / date / method / reference / notes
      and `journal_entry_id`.

  Returns `{:ok, payout}` (with `:payout_consultations` preloaded) or
  `{:error, reason}`.
  """
  def update_payout(%DoctorPayout{} = payout, attrs) do
    with {:ok, consultation_ids} <- fetch_consultation_ids(attrs),
         :ok <- validate_consultations_belong_to_doctor(consultation_ids, payout.doctor_id),
         {:ok, payout_date} <- fetch_date(attrs),
         {:ok, amount_cents} <- fetch_amount_cents(attrs),
         {:ok, iva_cents} <- fetch_retention_cents(attrs, :iva),
         {:ok, isr_cents} <- fetch_retention_cents(attrs, :isr),
         {:ok, payment_method} <- fetch_payment_method(attrs),
         {:ok, doctor} <- fetch_doctor(%{doctor_id: payout.doctor_id}) do
      transaction_result =
        Repo.transaction(fn ->
          with {:ok, new_je_id} <-
                 sync_journal_entry(
                   payout,
                   doctor,
                   consultation_ids,
                   payout_date,
                   amount_cents,
                   iva_cents,
                   isr_cents,
                   attrs
                 ),
               {:ok, updated} <-
                 update_payout_row(payout, %{
                   payout_date: payout_date,
                   amount_cents: amount_cents,
                   iva_retention_cents: iva_cents,
                   isr_retention_cents: isr_cents,
                   payment_method: payment_method,
                   reference: attrs[:reference],
                   notes: attrs[:notes],
                   journal_entry_id: new_je_id
                 }),
               :ok <- replace_payout_joins(payout.id, consultation_ids) do
            Repo.preload(updated, :payout_consultations, force: true)
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      case transaction_result do
        {:ok, p} -> {:ok, p}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # Reconciles the journal entry with the new amount + retentions. Returns
  # `{:ok, new_je_id_or_nil}`. The JE only exists when there's actual
  # bookkeeping to record (bank transfer OR either retention held).
  defp sync_journal_entry(
         %DoctorPayout{journal_entry_id: old_je_id},
         doctor,
         consultation_ids,
         payout_date,
         amount_cents,
         iva_cents,
         isr_cents,
         attrs
       ) do
    has_movement? = amount_cents > 0 or iva_cents > 0 or isr_cents > 0

    cond do
      # No-op: nothing to book, no JE existed
      not has_movement? and is_nil(old_je_id) ->
        {:ok, nil}

      # Now zero-movement: delete the existing JE
      not has_movement? ->
        :ok = delete_journal_entry(old_je_id)
        {:ok, nil}

      # Had no JE, now has movement: create one
      is_nil(old_je_id) ->
        case create_journal_entry(
               doctor,
               consultation_ids,
               payout_date,
               amount_cents,
               iva_cents,
               isr_cents,
               attrs
             ) do
          {:ok, je} -> {:ok, je.id}
          {:error, reason} -> {:error, reason}
        end

      # Had a JE, still has movement: update it in place
      true ->
        case update_journal_entry(
               old_je_id,
               doctor,
               consultation_ids,
               payout_date,
               amount_cents,
               iva_cents,
               isr_cents,
               attrs
             ) do
          {:ok, je} -> {:ok, je.id}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp delete_journal_entry(je_id) do
    Repo.delete_all(
      from jl in Ledgr.Core.Accounting.JournalLine, where: jl.journal_entry_id == ^je_id
    )

    Repo.delete_all(from je in Ledgr.Core.Accounting.JournalEntry, where: je.id == ^je_id)
    :ok
  end

  defp update_journal_entry(
         je_id,
         doctor,
         consultation_ids,
         payout_date,
         amount_cents,
         iva_cents,
         isr_cents,
         attrs
       ) do
    entry = Repo.get!(Ledgr.Core.Accounting.JournalEntry, je_id)

    {entry_attrs, lines} =
      journal_entry_payload(
        doctor,
        consultation_ids,
        payout_date,
        amount_cents,
        iva_cents,
        isr_cents,
        attrs
      )

    case Accounting.update_journal_entry_with_lines(entry, entry_attrs, lines) do
      {:ok, updated} ->
        {:ok, updated}

      {:error, changeset} ->
        Logger.error(
          "[HelloDoctor] Failed to update journal entry for doctor payout: #{inspect(changeset)}"
        )

        {:error, "failed to update journal entry"}
    end
  end

  defp update_payout_row(%DoctorPayout{} = payout, attrs) do
    payout
    |> DoctorPayout.changeset(attrs)
    |> Repo.update()
  end

  defp replace_payout_joins(payout_id, consultation_ids) do
    Repo.delete_all(from j in DoctorPayoutConsultation, where: j.doctor_payout_id == ^payout_id)

    insert_payout_joins(payout_id, consultation_ids)
  end

  @doc """
  For the edit page: returns consultations to show as checkboxes. Includes
  every consultation linked to *this* payout plus the doctor's other
  recent consultations (last 90 days around `payout_date`). Each row has
  `:linked_to_this_payout?` set so the template can default checkboxes
  and label "already paid out elsewhere" rows clearly.
  """
  def list_payout_edit_candidates(%DoctorPayout{} = payout) do
    linked_ids =
      payout
      |> Map.get(:payout_consultations, [])
      |> Enum.map(& &1.consultation_id)
      |> MapSet.new()

    start_date = Date.add(payout.payout_date, -90)
    end_date = Date.add(payout.payout_date, 90)

    rows =
      list_consultations_with_payouts(start_date, end_date, doctor_id: payout.doctor_id)

    # Make sure any linked consultations outside the 90-day window still appear.
    extra_ids =
      MapSet.difference(linked_ids, MapSet.new(rows, & &1.consultation_id))
      |> MapSet.to_list()

    extra_rows =
      case extra_ids do
        [] ->
          []

        ids ->
          # Pull just these by fetching with a wide enough window.
          all_rows =
            list_consultations_with_payouts(~D[2000-01-01], ~D[2100-01-01],
              doctor_id: payout.doctor_id
            )

          Enum.filter(all_rows, &(&1.consultation_id in ids))
      end

    (rows ++ extra_rows)
    |> Enum.uniq_by(& &1.consultation_id)
    |> Enum.map(fn r ->
      Map.put(r, :linked_to_this_payout?, MapSet.member?(linked_ids, r.consultation_id))
    end)
    # `:desc` shortcut uses default term ordering, which compares
    # NaiveDateTime field-by-field in alphabetical key order
    # (day before month — sorts May 29 above June 10). Dispatch through
    # NaiveDateTime.compare/2 instead.
    |> Enum.sort_by(&(&1.paid_at || ~N[1970-01-01 00:00:00]), {:desc, NaiveDateTime})
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
        {:error, "consultations don't belong to doctor #{doctor_id}: #{Enum.join(bad, ", ")}"}
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

  # Per-retention parser — accepts both `:iva_retention_cents`/`:iva` and
  # the equivalent ISR keys. Cents int, pesos float, or string pesos all
  # work, mirroring the `:amount` parser. Defaults to 0 when absent so
  # forms can omit the field.
  defp fetch_retention_cents(attrs, :iva),
    do: fetch_retention_cents_one(attrs, :iva_retention_cents, :iva)

  defp fetch_retention_cents(attrs, :isr),
    do: fetch_retention_cents_one(attrs, :isr_retention_cents, :isr)

  defp fetch_retention_cents_one(attrs, cents_key, pesos_key) do
    cents_value = Map.get(attrs, cents_key)
    pesos_value = Map.get(attrs, pesos_key)

    cond do
      is_integer(cents_value) and cents_value >= 0 ->
        {:ok, cents_value}

      is_binary(pesos_value) ->
        case Float.parse(String.trim(pesos_value)) do
          {pesos, ""} when pesos >= 0 -> {:ok, round(pesos * 100)}
          _ -> {:error, "invalid #{pesos_key}"}
        end

      is_float(pesos_value) and pesos_value >= 0 ->
        {:ok, round(pesos_value * 100)}

      is_integer(pesos_value) and pesos_value >= 0 ->
        {:ok, pesos_value * 100}

      true ->
        {:ok, 0}
    end
  end

  defp fetch_payment_method(%{payment_method: m}) when is_binary(m) do
    if m in DoctorPayout.payment_methods(),
      do: {:ok, m},
      else: {:error, "invalid payment_method"}
  end

  defp fetch_payment_method(_), do: {:ok, "bank_transfer"}

  defp create_journal_entry(
         doctor,
         consultation_ids,
         payout_date,
         amount_cents,
         iva_cents,
         isr_cents,
         attrs
       ) do
    {entry_attrs, lines} =
      journal_entry_payload(
        doctor,
        consultation_ids,
        payout_date,
        amount_cents,
        iva_cents,
        isr_cents,
        attrs
      )

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

  # Shared payload-builder used by both create and update so the JE body
  # stays in lockstep across the two paths.
  #
  # Gross obligation = amount + iva_retention + isr_retention. The JE
  # always clears that full gross from Doctor Payable; the credits split
  # between Bank (cash sent) and Taxes Payable (one line per retention
  # type, so SAT-side reporting can break IVA from ISR via the line
  # description). Any credit leg with a zero amount is omitted.
  defp journal_entry_payload(
         doctor,
         consultation_ids,
         payout_date,
         amount_cents,
         iva_cents,
         isr_cents,
         attrs
       ) do
    gross_cents = amount_cents + iva_cents + isr_cents

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

    debit_line = %{
      account_id: doctor_payable.id,
      debit_cents: gross_cents,
      credit_cents: 0,
      description: "Clearing doctor payable — #{doctor.name}"
    }

    bank_line =
      if amount_cents > 0 do
        [
          %{
            account_id: bank_mxn.id,
            debit_cents: 0,
            credit_cents: amount_cents,
            description: "Bank transfer to #{doctor.name}"
          }
        ]
      else
        []
      end

    # Fetch the Taxes Payable account at most once — only when we'll need it.
    taxes_payable_id =
      if iva_cents > 0 or isr_cents > 0 do
        Accounting.get_account_by_code!(@taxes_payable_code).id
      end

    iva_line =
      if iva_cents > 0 do
        [
          %{
            account_id: taxes_payable_id,
            debit_cents: 0,
            credit_cents: iva_cents,
            description: "IVA retention held back from #{doctor.name}"
          }
        ]
      else
        []
      end

    isr_line =
      if isr_cents > 0 do
        [
          %{
            account_id: taxes_payable_id,
            debit_cents: 0,
            credit_cents: isr_cents,
            description: "ISR retention held back from #{doctor.name}"
          }
        ]
      else
        []
      end

    {entry_attrs, [debit_line] ++ bank_line ++ iva_line ++ isr_line}
  end

  defp insert_payout_row(
         doctor_id,
         payout_date,
         amount_cents,
         iva_cents,
         isr_cents,
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
      iva_retention_cents: iva_cents,
      isr_retention_cents: isr_cents,
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

  # `paid_at` is UTC-stored. Plain `NaiveDateTime.to_date/1` returns
  # the UTC calendar date, off by a day for any payment that landed
  # after 6pm Mexico time. Shift to MX before taking the date.
  defp paid_date(ndt), do: Ledgr.Domains.HelloDoctor.to_mx_date(ndt)

  defp to_naive_start(%Date{} = d),
    do: Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive(d)

  defp to_naive_end_exclusive(%Date{} = d),
    do: Ledgr.Domains.HelloDoctor.mx_day_end_utc_naive(d)
end
