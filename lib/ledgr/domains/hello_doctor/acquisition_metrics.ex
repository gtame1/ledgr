defmodule Ledgr.Domains.HelloDoctor.AcquisitionMetrics do
  @moduledoc """
  Per-campaign acquisition funnel + daily lead trend for the HelloDoctor
  Meta ad attribution dashboard.

  Drives off a CTE that picks each conversation's first user message,
  applies the emoji detection from `Campaigns.detection_case_sql/1`, then
  measures each attributed conversation against TWO sources of truth:

    * **Early funnel stages** (greeting → payment_link_sent) come from
      `conversations.funnel_stage`, emitted as cumulative "reached this
      stage or later" counts.
    * **Outcome stages** (paid / consultation started / completed /
      cancelled / failed) come from the `consultations` and
      `stripe_payments` source tables — NOT from funnel_stage.

  ## Why outcomes don't come from funnel_stage

  `funnel_stage` only tracks the bot's *pre-consultation* chat state.
  Once a consultation is created the stage stops advancing — it stalls
  around `doctor_search`/`orientation` even for consultations that go on
  to complete or get cancelled. So the old cumulative
  `reached_N = COUNT(stage_idx >= N)` model (which assumed funnel_stage
  only moves forward) badly mismeasured every outcome KPI:

    * Paid was read from `funnel_stage = payment_confirmed` — but Stripe
      is the real record of payment.
    * Doctor-matched (`doctor_connected`) and Completed
      (`consultation_complete`) almost never appear in funnel_stage, so
      both read ~0 even with dozens of real completed consultations.
    * The "Completed" terminal even miscounted a `consultation_failed`
      (idx 12 ≥ 11) as a completion.

  The fix reads outcomes straight from the tables that own them:
  `consultations.status` (completed / cancelled / consultation_failed)
  and `stripe_payments.status` (paid / refunded). These outcome counts
  are independent per-conversation flags, NOT cumulative — Cancelled and
  Failed are SEPARATE terminal buckets, not "stages above Completed".

  ## Attribution model: first-touch per patient

  A patient's earliest attributed conversation (all-time, not just in
  the dashboard window) defines the campaign credit for *every*
  subsequent conversation that patient has — including organic return
  visits where the first message doesn't carry any campaign welcome
  text. This avoids dropping credit when a known patient comes back
  via WhatsApp directly instead of re-tapping the ad. Conversations
  with no `patient_id` (anonymous, no profile yet) fall through to
  per-conversation detection.

  Trade-off: a patient first acquired via GIN-01 who later taps a
  PED-01 ad credits GIN-01 for BOTH visits. PED-01 doesn't get credit
  for the re-engagement; it brought no genuinely new patient. This is
  the first-touch contract.

  ## Stage semantics

  Each per-campaign row has `reached_<N>` for N in 1..6 (the early
  funnel stages, cumulative) plus the independent outcome counts
  `paid`, `doctor_matched`, `completed`, `cancelled`, `failed`. Every
  prod `funnel_stage` at or beyond `payment_link_sent` (including
  post-payment states like `doctor_search` or `consultation_complete`)
  maps to idx 6 — it provably reached the payment link; whether it then
  paid / saw a doctor / completed is read from the source tables, not
  inferred from the (stalled) stage.

  Prod has stages the early list doesn't name explicitly
  (`consultation_type`, `payment_pending`, `code_validated`,
  `awaiting_recording_consent`); `@stage_idx_pairs` maps each onto its
  canonical early sibling so they're bucketed sensibly.

  `awaiting_code` and `abandoned` stay outside the chain — they're
  either pre-funnel (awaiting_code) or terminal-failure-outside
  (abandoned). `awaiting_code` in the direct pipe gets its own
  `pending_routing` counter.

  Attribution is content-based (emoji in the first user message), so it
  does NOT filter on `conversations.tenant`. Many ad-driven patients end
  up in `tenant = 'direct'` because the bot routes them through its
  referral-code question. Conversations paused at that yes/no
  button-tap are surfaced as the `pending_routing` KPI.

  DR-XXXX referral_link clicks (the per-doctor wa.me from the doctor
  show page) are excluded explicitly — separate acquisition path.

  Date range filters on `first_message_at` — the moment the patient hit
  the WhatsApp click-to-chat.
  """

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Campaigns
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting

  # Spend attribution for the estimated per-campaign CAC: these campaigns are our
  # Google ads (🩺 LPC-01, 🙏 LPH-01); every other campaign is Meta. Google spend
  # is split equally across the table's Google campaigns, Meta spend equally
  # across its Meta campaigns.
  @google_campaign_ids ~w(lpc_01 lph_01)

  @doc """
  Early funnel stages, in order, with display metadata. These are the
  stages we still trust `funnel_stage` for — everything up to and
  including `payment_link_sent`. The template iterates this list to
  render one cumulative column per stage; the outcome columns
  (`outcome_stages/0`) are rendered separately.
  """
  def canonical_stages do
    [
      %{idx: 1, key: :reached_1, stage: "greeting", label: "Greeting", short: "Greet"},
      %{idx: 2, key: :reached_2, stage: "symptoms", label: "Symptoms", short: "Sympt"},
      %{idx: 3, key: :reached_3, stage: "orientation", label: "Orientation", short: "Orient"},
      %{
        idx: 4,
        key: :reached_4,
        stage: "doctor_recommended",
        label: "Doctor recommended",
        short: "Dr rec"
      },
      %{
        idx: 5,
        key: :reached_5,
        stage: "consultation_type_set",
        label: "Consultation type set",
        short: "Type set"
      },
      %{
        idx: 6,
        key: :reached_6,
        stage: "payment_link_sent",
        label: "Payment link sent",
        short: "Pay link"
      }
    ]
  end

  @doc """
  Outcome stages, measured from the source tables (`consultations` +
  `stripe_payments`), NOT from `funnel_stage`. These are independent
  per-conversation counts, NOT cumulative: a conversation can be Paid
  without a consultation, and Cancelled/Failed are terminal buckets
  distinct from Completed (a completed conversation is excluded from
  both). The template renders these as a separate column group after
  the cumulative early stages.
  """
  def outcome_stages do
    [
      %{key: :paid, label: "Paid", short: "Paid", color: "#16a34a"},
      # Conversations that redeemed a promo/discount code (incl. 100%-off
      # $0 redemptions, which don't count as "paid").
      %{key: :discounted, label: "Discount used", short: "Disc", color: "#7c3aed"},
      %{
        key: :doctor_matched,
        label: "Consultation started",
        short: "Consult",
        color: "var(--text-main)"
      },
      %{key: :completed, label: "Completed", short: "Done", color: "var(--accent)"},
      %{key: :cancelled, label: "Cancelled", short: "Cancel", color: "#d97706"},
      %{key: :failed, label: "Failed", short: "Failed", color: "#dc2626"}
    ]
  end

  @doc """
  Patient lifecycle tiers (from `patient_segments`), rendered as a column
  group after the outcomes. Each cell is the count of DISTINCT attributed
  patients whose current tier is L1 (Engaged: ≥3 msgs, no consult), L2
  (Converted: 1 completed consult), or L3 (Core: ≥2 completed consults).
  L0 (leads / non-patients) is omitted — it's already covered by Leads /
  Patients. First-touch attribution, so a campaign keeps credit for the
  patients it brought even on their later (organic) conversations. Colors
  mirror `PatientSegments.tiers/0`.
  """
  def tier_stages do
    [
      %{key: :patients_l1, tier: "L1", label: "L1 Engaged", short: "L1", color: "#0ea5e9"},
      %{key: :patients_l2, tier: "L2", label: "L2 Converted", short: "L2", color: "#16a34a"},
      %{key: :patients_l3, tier: "L3", label: "L3 Core", short: "L3", color: "#7c3aed"}
    ]
  end

  # Maps every prod `funnel_stage` value onto an EARLY canonical idx
  # (1..6). Stages NOT in this list get NULL idx and don't count toward
  # any reached_<N>. Anything at or past payment_link_sent — including
  # post-payment / in-consultation / terminal states — maps to idx 6:
  # the conversation provably reached the payment link, and its true
  # outcome (paid / consultation / completed) is read from the source
  # tables, never from the (stalled) funnel_stage.
  @stage_idx_pairs [
    {"greeting", 1},
    # Direct-flow: code accepted, about to enter the funnel. Early.
    {"code_validated", 1},
    {"symptoms", 2},
    {"orientation", 3},
    {"doctor_recommended", 4},
    {"consultation_type", 5},
    {"consultation_type_set", 5},
    {"payment_link_sent", 6},
    {"payment_pending", 6},
    # Everything below is at/after payment_link_sent — clamp to idx 6.
    # The real outcome comes from consultations/stripe_payments.
    {"payment_confirmed", 6},
    {"data_collected", 6},
    {"doctor_search", 6},
    {"doctor_notified", 6},
    {"doctor_connected", 6},
    # Mid-consultation: the bot is asking to record the call. Post-pay.
    {"awaiting_recording_consent", 6},
    {"consultation_complete", 6},
    {"consultation_failed", 6}
  ]

  @doc "Default period: last 30 days inclusive, in Mexico City time."
  def last_30_days do
    today = Ledgr.Domains.HelloDoctor.today()
    {Date.add(today, -29), today}
  end

  @doc """
  Returns `%{period, totals, per_campaign, daily}` for the date range.

    * `per_campaign` — list of maps keyed by campaign id, with `leads`,
      `unique_patients`, `pending_routing`, `reached_1`..`reached_6`,
      the outcome counts `paid`/`doctor_matched`/`completed`/
      `cancelled`/`failed`, `revenue_mxn`, and `*_pct` percentages.
    * `daily` — list of `%{date, by_campaign: %{id => leads}, total}`
      rows for the trend chart.
    * `totals` — sum across campaigns.

  Unattributed conversations are NOT counted — this is strictly the
  ad-attributed funnel.
  """
  def generate(start_date, end_date) do
    base = funnel(start_date, end_date)

    # Mexico City wall-clock bounds → UTC instants. See
    # `Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive/1`.
    start_naive = Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive(start_date)
    end_exclusive = Ledgr.Domains.HelloDoctor.mx_day_end_utc_naive(end_date)
    daily = run_daily_query(start_naive, end_exclusive, start_date, end_date)

    Map.put(base, :daily, daily)
  end

  @doc """
  Per-campaign funnel for a date window, WITHOUT the daily trend chart.
  Returns `%{period, per_campaign, totals}`.

  This is what the cutoff-era sub-tables use — they only need the table,
  not the chart, and they query their own (narrower) window. An empty or
  inverted window (`start_date > end_date`, e.g. when the picker range
  doesn't overlap an era at all) yields all-zero rows instead of running
  a query.
  """
  def funnel(start_date, end_date) do
    rows =
      if Date.compare(start_date, end_date) == :gt do
        %{}
      else
        start_naive = Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive(start_date)
        end_exclusive = Ledgr.Domains.HelloDoctor.mx_day_end_utc_naive(end_date)
        run_funnel_query(start_naive, end_exclusive)
      end

    per_campaign =
      Campaigns.all()
      |> Enum.map(fn c ->
        r = Map.get(rows, c.id, empty_row())
        Map.merge(%{campaign: c}, decorate(r))
      end)

    %{
      period: {start_date, end_date},
      per_campaign: per_campaign,
      totals: totals(per_campaign)
    }
  end

  @doc """
  Totals row for an arbitrary subset of the `per_campaign` list — same
  shape as `report.totals`. Used to give an era sub-table its own footer
  + column-share denominators, independent of the all-campaigns totals.
  """
  def subtotals(per_campaign_subset), do: totals(per_campaign_subset)

  @doc """
  One ready-to-render funnel table per tracking era (see
  `Campaigns.eras/0`), **newest first**. Each era's window is its
  `[lower, upper)` boundary intersected with the page's `[start, end]`
  range, so the From/To picker still bounds the page while every table's
  numbers auto-split at the cuts.

  Each entry: `%{lower, upper, current?, window: {s, e}, empty?, entries,
  totals}`. `entries` is the era's campaigns decorated for its window;
  `empty?` is true when the picker range doesn't overlap the era at all
  (window inverts) — the template shows a note instead of a table.
  """
  def cut_tables(start_date, end_date) do
    Campaigns.eras()
    |> Enum.map(fn era ->
      win_start = if era.lower, do: max_date(era.lower, start_date), else: start_date
      win_end = if era.upper, do: min_date(Date.add(era.upper, -1), end_date), else: end_date

      report = funnel(win_start, win_end)
      ids = MapSet.new(era.campaign_ids)
      entries = Enum.filter(report.per_campaign, &(&1.campaign.id in ids))
      {entries, table_ad_spend} = with_est_cac(entries, era.campaign_ids, win_start, win_end)

      totals =
        entries
        |> subtotals()
        |> then(fn t ->
          cost = table_ad_spend + (t.free_consult_mxn || 0.0)

          Map.merge(t, %{
            est_ad_spend: Float.round(table_ad_spend, 2),
            est_cost: Float.round(cost, 2),
            est_cac: cac_div(cost, t.completed)
          })
        end)

      %{
        lower: era.lower,
        upper: era.upper,
        current?: is_nil(era.upper),
        window: {win_start, win_end},
        empty?: Date.compare(win_start, win_end) == :gt,
        entries: entries,
        totals: totals
      }
    end)
    |> Enum.reverse()
  end

  defp min_date(a, b), do: if(Date.compare(a, b) == :gt, do: b, else: a)
  defp max_date(a, b), do: if(Date.compare(a, b) == :lt, do: b, else: a)

  # ── Estimated per-campaign CAC ──────────────────────────────────
  # Google spend split equally across the era's Google campaigns; Meta spend
  # equally across its Meta campaigns. CAC = (allocated ad spend + the campaign's
  # free-consult subsidy) ÷ DONE (completed) consults — matching the Unit
  # Economics blended CAC. nil (rendered "—") when the campaign has 0 completed.
  # Returns {enriched_entries, total_allocated_ad_spend}.
  defp with_est_cac(entries, era_campaign_ids, win_start, win_end) do
    spend = spend_by_platform(win_start, win_end)
    google = Map.get(spend, "google", 0.0)
    meta = Map.get(spend, "meta", 0.0)

    google_ids = Enum.filter(era_campaign_ids, &(&1 in @google_campaign_ids))
    meta_ids = Enum.reject(era_campaign_ids, &(&1 in @google_campaign_ids))
    google_each = if google_ids == [], do: 0.0, else: google / length(google_ids)
    meta_each = if meta_ids == [], do: 0.0, else: meta / length(meta_ids)

    enriched =
      Enum.map(entries, fn e ->
        ad = if e.campaign.id in @google_campaign_ids, do: google_each, else: meta_each
        free = e.free_consult_mxn || 0.0

        Map.merge(e, %{
          est_ad_spend: Float.round(ad, 2),
          est_cost: Float.round(ad + free, 2),
          est_cac: cac_div(ad + free, e.completed)
        })
      end)

    total_ad = Enum.reduce(enriched, 0.0, fn e, acc -> acc + e.est_ad_spend end)
    {enriched, total_ad}
  end

  # Marketing spend (MXN) per platform for a Mexico-City calendar window,
  # keyed by lowercased platform. `marketing_costs.date` is a real date column.
  defp spend_by_platform(win_start, win_end) do
    sql = """
    SELECT lower(platform) AS platform,
           SUM(COALESCE(spend_mxn_cents,
                        CASE WHEN currency = 'MXN' THEN round(amount * 100) ELSE 0 END)) / 100.0 AS mxn
    FROM marketing_costs
    WHERE date >= $1 AND date <= $2
    GROUP BY 1
    """

    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [win_start, win_end])
    cols = Enum.map(result.columns, &String.to_atom/1)

    result.rows
    |> Enum.map(fn row -> cols |> Enum.zip(row) |> Map.new() end)
    |> Enum.into(%{}, fn r -> {r.platform, to_float(r.mxn)} end)
  rescue
    # marketing_costs may not exist in some envs — treat as no spend.
    _ -> %{}
  end

  # CAC = spend ÷ paid; nil (rendered "—") when there are no paid consults.
  defp cac_div(_spend, paid) when paid in [0, nil], do: nil
  defp cac_div(spend, paid) when is_number(paid) and paid > 0, do: Float.round(spend / paid, 2)
  defp cac_div(_, _), do: nil

  # ── Per-campaign funnel ─────────────────────────────────────────

  defp run_funnel_query(start_naive, end_exclusive) do
    detection = Campaigns.detection_case_sql("fm.content")

    # Tenant-aware doctor share, for the free-consult subsidy (the cost HD
    # absorbs on a comped completed consult — patient charged $0 but the doctor
    # is still paid). Bound to the conv_cons joins below.
    free_share_sql =
      ConsultationAccounting.doctor_share_sql("conv2.tenant", "d.consultation_fee_mxn")

    # Emit `('greeting', 1), ('symptoms', 2), ...` for the SQL VALUES list.
    stage_values_sql =
      @stage_idx_pairs
      |> Enum.map_join(", ", fn {s, i} -> "('#{s}', #{i})" end)

    # Emit `COUNT(*) FILTER (WHERE a.stage_idx >= 1) AS reached_1, ...`
    reached_select =
      canonical_stages()
      |> Enum.map_join(",\n      ", fn s ->
        "COUNT(*) FILTER (WHERE a.stage_idx >= #{s.idx}) AS reached_#{s.idx}"
      end)

    sql = """
    WITH funnel_stages(stage, idx) AS (VALUES #{stage_values_sql}),
    first_msg AS (
      SELECT DISTINCT ON (m.conversation_id)
        m.conversation_id,
        m.content,
        m.created_at AS first_msg_at
      FROM messages m
      WHERE m.role = 'user'
      ORDER BY m.conversation_id, m.created_at ASC
    ),
    -- All conversations EVER + their direct per-message campaign match.
    -- No date filter: first-touch attribution needs to see history
    -- before the dashboard window so it can credit an out-of-period
    -- ad click for an in-period return conversation.
    detected_all AS (
      SELECT
        fm.conversation_id,
        fm.first_msg_at,
        c.patient_id,
        c.funnel_stage,
        c.tenant,
        COALESCE(fs.idx, 0) AS stage_idx,
        #{detection} AS direct_campaign_id
      FROM first_msg fm
      JOIN conversations c ON c.id = fm.conversation_id
      LEFT JOIN funnel_stages fs ON fs.stage = c.funnel_stage
      -- DR-XXXX referral_link clicks (per-doctor wa.me from the doctor
      -- show page) aren't ad-attributable. Same prefix the bot uses.
      WHERE fm.content NOT ILIKE '%mi doctor: dr-%'
    ),
    -- First-touch: each patient's earliest attributed conversation
    -- defines the campaign that gets credit for every subsequent
    -- conversation by that patient (even ones whose first message
    -- doesn't match any campaign welcome-text — organic returns).
    -- Anonymous conversations (patient_id NULL) can't be deduped this
    -- way; they fall through to direct per-conversation detection.
    patient_first_campaign AS (
      SELECT DISTINCT ON (patient_id)
        patient_id, direct_campaign_id
      FROM detected_all
      WHERE direct_campaign_id IS NOT NULL
        AND patient_id IS NOT NULL
      ORDER BY patient_id, first_msg_at ASC
    ),
    attributed AS (
      SELECT
        da.conversation_id,
        da.first_msg_at,
        da.patient_id,
        da.funnel_stage,
        da.tenant,
        da.stage_idx,
        -- Inherit from the patient's first-touch when available;
        -- otherwise fall back to per-conversation detection (covers
        -- patient_id IS NULL and patients whose every conversation
        -- including the earliest doesn't match a campaign).
        COALESCE(pfc.direct_campaign_id, da.direct_campaign_id) AS campaign_id
      FROM detected_all da
      LEFT JOIN patient_first_campaign pfc ON pfc.patient_id = da.patient_id
      -- Window applied AFTER inheriting so out-of-period first-touches
      -- still credit in-period followups.
      WHERE da.first_msg_at >= $1 AND da.first_msg_at < $2
    ),
    -- Per-conversation consultation outcome flags, from the table that
    -- actually owns them. funnel_stage stalls once a consultation is
    -- created, so these can't be inferred from the chat state.
    conv_cons AS (
      SELECT
        cs.conversation_id,
        COUNT(*) AS n_consultations,
        bool_or(cs.status = 'completed') AS has_completed,
        bool_or(cs.status = 'cancelled') AS has_cancelled,
        bool_or(cs.status = 'consultation_failed') AS has_failed,
        -- Free-consult subsidy: doctor share HD absorbs on a COMPLETED but
        -- uncharged (comped, $0) consult — the experiment first-consult cost.
        COALESCE(SUM(
          CASE WHEN cs.status = 'completed' AND COALESCE(cs.payment_amount, 0) = 0
               THEN #{free_share_sql} ELSE 0 END
        ), 0) AS free_consult_cost
      FROM consultations cs
      LEFT JOIN conversations conv2 ON conv2.id = cs.conversation_id
      LEFT JOIN doctors d ON d.id = cs.doctor_id
      WHERE cs.conversation_id IS NOT NULL
      GROUP BY cs.conversation_id
    ),
    -- Resolve each Stripe payment to a single conversation. Only 7/20
    -- paid rows carry consultation_id directly; the rest link by
    -- payment_intent matching the consultation's. The OR-join can match
    -- a payment to >1 consultation (re-broadcast → 2 consultations,
    -- same intent), so DISTINCT ON (sp.id) collapses to one row and
    -- prevents double-counting revenue / paid.
    payment_conv AS (
      SELECT DISTINCT ON (sp.id)
        sp.id AS payment_id,
        cons.conversation_id,
        sp.status,
        sp.amount,
        sp.amount_refunded,
        sp.discount_code
      FROM stripe_payments sp
      JOIN consultations cons ON (
        cons.id = sp.consultation_id
        OR (sp.consultation_id IS NULL
            AND sp.stripe_payment_intent_id IS NOT NULL
            AND sp.stripe_payment_intent_id = cons.stripe_payment_intent_id)
      )
      WHERE cons.conversation_id IS NOT NULL
      ORDER BY sp.id, cons.assigned_at ASC
    ),
    conv_pay AS (
      SELECT
        conversation_id,
        bool_or(status = 'paid') AS has_paid,
        -- Any promo/discount code applied at checkout — INCLUDING 100%-off
        -- redemptions (status 'no_payment', $0 charged) so free uses count.
        bool_or(discount_code IS NOT NULL) AS used_discount,
        -- Net of refunds: a fully-refunded payment (status='refunded')
        -- and a partial refund on a still-'paid' row both reduce to
        -- (amount - amount_refunded). Excludes non-settled statuses.
        COALESCE(
          SUM(COALESCE(amount, 0) - COALESCE(amount_refunded, 0))
            FILTER (WHERE status IN ('paid', 'refunded')),
          0
        ) AS net_revenue
      FROM payment_conv
      GROUP BY conversation_id
    ),
    -- All-time active-day count per patient. "Returning" = active on >= 2
    -- distinct Mexico-City days (message-based), independent of the window
    -- — we want to know if the campaign's patients ever came back at all.
    patient_days AS (
      SELECT c.patient_id AS pid,
             COUNT(DISTINCT (
               (m.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date
             )) AS active_days
      FROM messages m
      JOIN conversations c ON c.id = m.conversation_id
      WHERE m.role = 'user' AND c.patient_id IS NOT NULL
      GROUP BY c.patient_id
    )
    SELECT
      a.campaign_id,
      COUNT(*) AS leads,
      COUNT(DISTINCT a.patient_id) AS unique_patients,
      -- Distinct attributed patients who returned (active >= 2 MX days).
      COUNT(DISTINCT a.patient_id) FILTER (WHERE pd.active_days >= 2) AS returning_patients,
      -- Ad clicks paused at the bot's "¿te refirió un doctor?" prompt.
      -- Transient — empirically avg ~7h before tapping a button.
      COUNT(*) FILTER (
        WHERE a.tenant = 'direct' AND a.funnel_stage = 'awaiting_code'
      ) AS pending_routing,
      #{reached_select},
      -- Outcomes: independent per-conversation counts from source tables.
      COUNT(*) FILTER (WHERE cp.has_paid) AS paid,
      COUNT(*) FILTER (WHERE cp.used_discount) AS discounted,
      COUNT(*) FILTER (WHERE cc.n_consultations > 0) AS doctor_matched,
      COUNT(*) FILTER (WHERE cc.has_completed) AS completed,
      -- Terminal buckets exclude conversations that also completed, so
      -- they read as distinct outcomes rather than stages above Done.
      COUNT(*) FILTER (
        WHERE cc.has_cancelled AND NOT COALESCE(cc.has_completed, false)
      ) AS cancelled,
      COUNT(*) FILTER (
        WHERE cc.has_failed AND NOT COALESCE(cc.has_completed, false)
      ) AS failed,
      -- Patient lifecycle tier (from patient_segments): distinct attributed
      -- patients whose current tier is L1/L2/L3. Patient-quality per campaign.
      COUNT(DISTINCT a.patient_id) FILTER (WHERE COALESCE(ps.tier, 'L0') = 'L1') AS patients_l1,
      COUNT(DISTINCT a.patient_id) FILTER (WHERE COALESCE(ps.tier, 'L0') = 'L2') AS patients_l2,
      COUNT(DISTINCT a.patient_id) FILTER (WHERE COALESCE(ps.tier, 'L0') = 'L3') AS patients_l3,
      COALESCE(SUM(cp.net_revenue), 0) AS revenue_mxn,
      COALESCE(SUM(cc.free_consult_cost), 0) AS free_consult_mxn
    FROM attributed a
    LEFT JOIN conv_cons cc ON cc.conversation_id = a.conversation_id
    LEFT JOIN conv_pay cp ON cp.conversation_id = a.conversation_id
    LEFT JOIN patient_days pd ON pd.pid = a.patient_id
    LEFT JOIN patient_segments ps ON ps.patient_id = a.patient_id
    WHERE a.campaign_id IS NOT NULL
    GROUP BY a.campaign_id
    """

    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [start_naive, end_exclusive])

    columns = Enum.map(result.columns, &String.to_atom/1)

    result.rows
    |> Enum.map(fn row -> columns |> Enum.zip(row) |> Map.new() end)
    |> Enum.into(%{}, fn row -> {row.campaign_id, row} end)
  end

  defp empty_row do
    base = %{
      leads: 0,
      unique_patients: 0,
      returning_patients: 0,
      pending_routing: 0,
      revenue_mxn: 0,
      free_consult_mxn: 0
    }

    keys =
      Enum.map(canonical_stages(), & &1.key) ++
        Enum.map(outcome_stages(), & &1.key) ++
        Enum.map(tier_stages(), & &1.key)

    Enum.reduce(keys, base, fn k, acc -> Map.put(acc, k, 0) end)
  end

  defp decorate(row) do
    leads = row.leads || 0

    # Early-stage cumulative counts (defensive: SQL returns 0 not nil
    # after COUNT, but `empty_row` cells fall through to here too).
    reached =
      Enum.reduce(canonical_stages(), %{}, fn s, acc ->
        Map.put(acc, s.key, Map.get(row, s.key) || 0)
      end)

    # Per-stage `pct_<N>` for hover tooltips.
    reached_pcts =
      Enum.reduce(canonical_stages(), %{}, fn s, acc ->
        pct_key = :"pct_#{s.idx}"
        Map.put(acc, pct_key, pct(Map.get(reached, s.key), leads))
      end)

    # Outcome counts (paid/doctor_matched/completed/cancelled/failed)
    # straight off the row, plus each one's share of leads for tooltips.
    outcomes =
      Enum.reduce(outcome_stages(), %{}, fn s, acc ->
        Map.put(acc, s.key, Map.get(row, s.key) || 0)
      end)

    outcome_pcts =
      Enum.reduce(outcome_stages(), %{}, fn s, acc ->
        Map.put(acc, :"pct_#{s.key}", pct(Map.get(outcomes, s.key), leads))
      end)

    # Lifecycle-tier patient counts, plus each tier's share of the campaign's
    # unique patients (for the hover tooltip).
    unique_patients = row.unique_patients || 0

    tiers =
      Enum.reduce(tier_stages(), %{}, fn s, acc ->
        Map.put(acc, s.key, Map.get(row, s.key) || 0)
      end)

    tier_pcts =
      Enum.reduce(tier_stages(), %{}, fn s, acc ->
        Map.put(acc, :"pct_#{s.key}", pct(Map.get(tiers, s.key), unique_patients))
      end)

    base = %{
      leads: leads,
      unique_patients: row.unique_patients || 0,
      returning_patients: row[:returning_patients] || 0,
      # Share of the campaign's unique patients who came back (≥2 MX days).
      returning_rate: pct(row[:returning_patients] || 0, row.unique_patients || 0),
      pending_routing: row[:pending_routing] || 0,
      revenue_mxn: to_float(row.revenue_mxn),
      free_consult_mxn: to_float(row[:free_consult_mxn]),
      pending_routing_pct: pct(row[:pending_routing] || 0, leads)
    }

    # KPI-card aliases. `triaged` is still an early funnel stage
    # (doctor_recommended, idx 4); the rest now point at the
    # source-of-truth outcome counts so cards and table agree.
    aliases = %{
      triaged: Map.get(reached, :reached_4),
      lead_to_paid: pct(Map.get(outcomes, :paid), leads),
      lead_to_completed: pct(Map.get(outcomes, :completed), leads)
    }

    base
    |> Map.merge(reached)
    |> Map.merge(reached_pcts)
    |> Map.merge(outcomes)
    |> Map.merge(outcome_pcts)
    |> Map.merge(tiers)
    |> Map.merge(tier_pcts)
    |> Map.merge(aliases)
  end

  defp pct(_n, 0), do: 0.0
  defp pct(nil, _), do: 0.0
  defp pct(n, d), do: Float.round(n / d * 100, 1)

  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(n) when is_float(n), do: n

  defp totals(per_campaign) do
    summed_keys =
      [
        :leads,
        :unique_patients,
        :returning_patients,
        :pending_routing,
        :revenue_mxn,
        :free_consult_mxn
      ] ++
        Enum.map(canonical_stages(), & &1.key) ++
        Enum.map(outcome_stages(), & &1.key) ++
        Enum.map(tier_stages(), & &1.key)

    summed =
      Enum.reduce(summed_keys, %{}, fn k, acc ->
        sum =
          per_campaign
          |> Enum.map(&Map.get(&1, k, 0))
          |> Enum.reduce(0, fn v, s -> s + (v || 0) end)

        Map.put(acc, k, if(k == :revenue_mxn, do: Float.round(sum / 1, 2), else: sum))
      end)

    leads = summed.leads

    # KPI aliases at the totals level (see `decorate/1`).
    aliases = %{
      triaged: Map.get(summed, :reached_4),
      lead_to_paid: pct(Map.get(summed, :paid), leads),
      lead_to_completed: pct(Map.get(summed, :completed), leads),
      pending_routing_pct: pct(summed.pending_routing, leads),
      returning_rate: pct(Map.get(summed, :returning_patients), Map.get(summed, :unique_patients))
    }

    # Per-column % of leads, for the totals row in the table — both the
    # cumulative early stages and the outcome columns.
    pct_rolls =
      Enum.reduce(canonical_stages(), %{}, fn s, acc ->
        Map.put(acc, :"pct_#{s.idx}", pct(Map.get(summed, s.key), leads))
      end)

    outcome_pct_rolls =
      Enum.reduce(outcome_stages(), %{}, fn s, acc ->
        Map.put(acc, :"pct_#{s.key}", pct(Map.get(summed, s.key), leads))
      end)

    # Tier columns roll up as a share of all unique patients (not leads).
    tier_pct_rolls =
      Enum.reduce(tier_stages(), %{}, fn s, acc ->
        Map.put(
          acc,
          :"pct_#{s.key}",
          pct(Map.get(summed, s.key), Map.get(summed, :unique_patients))
        )
      end)

    summed
    |> Map.merge(aliases)
    |> Map.merge(pct_rolls)
    |> Map.merge(outcome_pct_rolls)
    |> Map.merge(tier_pct_rolls)
  end

  # ── Daily trend ──────────────────────────────────────────────────

  defp run_daily_query(start_naive, end_exclusive, start_date, end_date) do
    detection = Campaigns.detection_case_sql("fm.content")

    # Same first-touch attribution as `run_funnel_query/2` so the
    # daily chart and per-campaign table show identical lead counts.
    sql = """
    WITH first_msg AS (
      SELECT DISTINCT ON (m.conversation_id)
        m.conversation_id,
        m.content,
        m.created_at AS first_msg_at
      FROM messages m
      WHERE m.role = 'user'
      ORDER BY m.conversation_id, m.created_at ASC
    ),
    detected_all AS (
      SELECT
        fm.conversation_id, fm.first_msg_at, c.patient_id,
        #{detection} AS direct_campaign_id
      FROM first_msg fm
      JOIN conversations c ON c.id = fm.conversation_id
      WHERE fm.content NOT ILIKE '%mi doctor: dr-%'
    ),
    patient_first_campaign AS (
      SELECT DISTINCT ON (patient_id) patient_id, direct_campaign_id
      FROM detected_all
      WHERE direct_campaign_id IS NOT NULL AND patient_id IS NOT NULL
      ORDER BY patient_id, first_msg_at ASC
    ),
    attributed AS (
      SELECT
        -- MX-date bucket, not UTC date — see
        -- Ledgr.Domains.HelloDoctor.to_mx_date/1 for the Elixir-side
        -- twin of this expression.
        DATE((da.first_msg_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')) AS day,
        COALESCE(pfc.direct_campaign_id, da.direct_campaign_id) AS campaign_id
      FROM detected_all da
      LEFT JOIN patient_first_campaign pfc ON pfc.patient_id = da.patient_id
      WHERE da.first_msg_at >= $1 AND da.first_msg_at < $2
    )
    SELECT day, campaign_id, COUNT(*) AS leads
    FROM attributed
    WHERE campaign_id IS NOT NULL
    GROUP BY day, campaign_id
    ORDER BY day ASC, campaign_id
    """

    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [start_naive, end_exclusive])

    # Group into one row per calendar day, filling 0 for missing campaigns.
    raw =
      result.rows
      |> Enum.map(fn [day, campaign_id, leads] -> {day, campaign_id, leads} end)
      |> Enum.group_by(fn {day, _, _} -> day end, fn {_, c, l} -> {c, l} end)

    days = Date.range(start_date, end_date) |> Enum.to_list()

    Enum.map(days, fn day ->
      entries = Map.get(raw, day, [])
      by_campaign = Map.new(entries)
      total = entries |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      %{date: day, by_campaign: by_campaign, total: total}
    end)
  end
end
