defmodule Ledgr.Domains.HelloDoctor.AcquisitionMetrics do
  @moduledoc """
  Per-campaign acquisition funnel + daily lead trend for the HelloDoctor
  Meta ad attribution dashboard.

  Drives off a CTE that picks each conversation's first user message,
  applies the emoji+phrase detection from `Campaigns.detection_case_sql/1`,
  then maps each conversation's current `funnel_stage` to a canonical
  stage index and emits cumulative "reached this stage or later" counts.

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

  Each per-campaign row has a `reached_<N>` field for N in 1..12, where N
  follows the canonical ordering defined in
  `Ledgr.Domains.HelloDoctor.ConversationFunnelExport`. Cumulative: a
  conversation in `consultation_complete` (idx 11) is counted in every
  `reached_<N>` for N ≤ 11. The implicit assumption — same as the
  conversation funnel CSV — is that the bot only advances funnel_stage
  forward over time; if that assumption breaks we'd undercount.

  Prod has stages the canonical list doesn't name explicitly
  (`consultation_type`, `payment_pending`, `doctor_notified`); the
  `@stage_idx` VALUES list maps them onto the canonical sibling so
  they're bucketed sensibly (a `payment_pending` conversation counts as
  having reached `payment_link_sent`, not the void).

  `awaiting_code` and `abandoned` stay outside the canonical chain —
  they're either pre-funnel (awaiting_code) or terminal-failure-outside
  (abandoned). `awaiting_code` in the direct pipe gets its own
  `pending_routing` counter.

  Attribution is content-based (emoji + phrase in the first user
  message), so it does NOT filter on `conversations.tenant`. Many
  ad-driven patients end up in `tenant = 'direct'` because the bot
  routes them through its referral-code question. Conversations paused
  at that yes/no button-tap are surfaced as the `pending_routing` KPI.

  DR-XXXX referral_link clicks (the per-doctor wa.me from the doctor
  show page) are excluded explicitly — separate acquisition path.

  Date range filters on `first_message_at` — the moment the patient hit
  the WhatsApp click-to-chat.
  """

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Campaigns

  @doc """
  Canonical funnel stages, in order, with display metadata.

  Mirrors the VALUES list in `ConversationFunnelExport.build_query/1`
  exactly — same idx for every shared stage name. The template iterates
  this list to render one column per stage.
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
      },
      %{
        idx: 7,
        key: :reached_7,
        stage: "payment_confirmed",
        label: "Payment confirmed",
        short: "Pay cnf"
      },
      %{
        idx: 8,
        key: :reached_8,
        stage: "data_collected",
        label: "Data collected",
        short: "Data"
      },
      %{
        idx: 9,
        key: :reached_9,
        stage: "doctor_search",
        label: "Doctor search",
        short: "Dr search"
      },
      %{
        idx: 10,
        key: :reached_10,
        stage: "doctor_connected",
        label: "Doctor connected",
        short: "Dr conn"
      },
      %{
        idx: 11,
        key: :reached_11,
        stage: "consultation_complete",
        label: "Consultation complete",
        short: "Done"
      },
      %{
        idx: 12,
        key: :reached_12,
        stage: "consultation_failed",
        label: "Consultation failed",
        short: "Failed"
      }
    ]
  end

  # Maps every prod `funnel_stage` value onto a canonical idx (1..12).
  # Stages NOT in this list get NULL idx and don't count toward any
  # reached_<N>. Variants (consultation_type, payment_pending,
  # doctor_notified) bucket to their canonical sibling.
  @stage_idx_pairs [
    {"greeting", 1},
    {"symptoms", 2},
    {"orientation", 3},
    {"doctor_recommended", 4},
    {"consultation_type", 5},
    {"consultation_type_set", 5},
    {"payment_link_sent", 6},
    {"payment_pending", 6},
    {"payment_confirmed", 7},
    {"data_collected", 8},
    {"doctor_search", 9},
    {"doctor_notified", 10},
    {"doctor_connected", 10},
    {"consultation_complete", 11},
    {"consultation_failed", 12}
  ]

  @doc "Default period: last 30 days inclusive, in Mexico City time."
  def last_30_days do
    today = Ledgr.Domains.HelloDoctor.today()
    {Date.add(today, -29), today}
  end

  @doc """
  Returns `%{period, totals, per_campaign, daily}` for the date range.

    * `per_campaign` — list of maps keyed by campaign id, with `leads`,
      `unique_patients`, `pending_routing`, `reached_1`..`reached_12`,
      `revenue_mxn`, and `*_pct` percentages of leads.
    * `daily` — list of `%{date, by_campaign: %{id => leads}, total}`
      rows for the trend chart.
    * `totals` — sum across campaigns.

  Unattributed conversations are NOT counted — this is strictly the
  ad-attributed funnel.
  """
  def generate(start_date, end_date) do
    # Mexico City wall-clock bounds → UTC instants. See
    # `Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive/1`.
    start_naive = Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive(start_date)
    end_exclusive = Ledgr.Domains.HelloDoctor.mx_day_end_utc_naive(end_date)

    rows = run_funnel_query(start_naive, end_exclusive)
    daily = run_daily_query(start_naive, end_exclusive, start_date, end_date)

    per_campaign =
      Campaigns.all()
      |> Enum.map(fn c ->
        r = Map.get(rows, c.id, empty_row())
        Map.merge(%{campaign: c}, decorate(r))
      end)

    %{
      period: {start_date, end_date},
      per_campaign: per_campaign,
      daily: daily,
      totals: totals(per_campaign)
    }
  end

  # ── Per-campaign funnel ─────────────────────────────────────────

  defp run_funnel_query(start_naive, end_exclusive) do
    detection = Campaigns.detection_case_sql("fm.content")

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
    )
    SELECT
      a.campaign_id,
      COUNT(*) AS leads,
      COUNT(DISTINCT a.patient_id) AS unique_patients,
      -- Ad clicks paused at the bot's "¿te refirió un doctor?" prompt.
      -- Transient — empirically avg ~7h before tapping a button.
      COUNT(*) FILTER (
        WHERE a.tenant = 'direct' AND a.funnel_stage = 'awaiting_code'
      ) AS pending_routing,
      #{reached_select},
      COALESCE(SUM(sp.amount) FILTER (WHERE sp.status = 'paid'), 0) AS revenue_mxn
    FROM attributed a
    LEFT JOIN consultations cons ON cons.conversation_id = a.conversation_id
    LEFT JOIN stripe_payments sp ON (
      sp.consultation_id = cons.id
      OR (sp.consultation_id IS NULL
          AND cons.stripe_payment_intent_id IS NOT NULL
          AND sp.stripe_payment_intent_id = cons.stripe_payment_intent_id)
    )
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
      pending_routing: 0,
      revenue_mxn: 0
    }

    Enum.reduce(canonical_stages(), base, fn s, acc -> Map.put(acc, s.key, 0) end)
  end

  defp decorate(row) do
    leads = row.leads || 0

    # Per-stage counts (defensive: SQL returns 0 not nil after COUNT, but
    # `empty_row` cells fall through to here too).
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

    base = %{
      leads: leads,
      unique_patients: row.unique_patients || 0,
      pending_routing: row[:pending_routing] || 0,
      revenue_mxn: to_float(row.revenue_mxn),
      pending_routing_pct: pct(row[:pending_routing] || 0, leads)
    }

    # Backward-compat aliases for the top-of-page KPI cards. Mapping:
    #   triaged        = reached doctor_recommended (idx 4)
    #   doctor_matched = reached doctor_connected   (idx 10)
    #   paid           = reached payment_confirmed  (idx 7)
    #   completed      = reached consultation_complete (idx 11)
    # The old KPIs used a mix of `consultations.status` and funnel_stage
    # filters; this unifies on funnel_stage so the KPI cards and the
    # per-stage table agree.
    aliases = %{
      triaged: Map.get(reached, :reached_4),
      doctor_matched: Map.get(reached, :reached_10),
      paid: Map.get(reached, :reached_7),
      completed: Map.get(reached, :reached_11),
      lead_to_paid: pct(Map.get(reached, :reached_7), leads),
      lead_to_completed: pct(Map.get(reached, :reached_11), leads)
    }

    base
    |> Map.merge(reached)
    |> Map.merge(reached_pcts)
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
      [:leads, :unique_patients, :pending_routing, :revenue_mxn] ++
        Enum.map(canonical_stages(), & &1.key)

    summed =
      Enum.reduce(summed_keys, %{}, fn k, acc ->
        sum =
          per_campaign
          |> Enum.map(&Map.get(&1, k, 0))
          |> Enum.reduce(0, fn v, s -> s + (v || 0) end)

        Map.put(acc, k, if(k == :revenue_mxn, do: Float.round(sum / 1, 2), else: sum))
      end)

    leads = summed.leads

    # Roll up the same backward-compat KPI aliases at the totals level.
    aliases = %{
      triaged: Map.get(summed, :reached_4),
      doctor_matched: Map.get(summed, :reached_10),
      paid: Map.get(summed, :reached_7),
      completed: Map.get(summed, :reached_11),
      lead_to_paid: pct(Map.get(summed, :reached_7), leads),
      lead_to_completed: pct(Map.get(summed, :reached_11), leads),
      pending_routing_pct: pct(summed.pending_routing, leads)
    }

    # Per-stage % too, for the totals row in the table.
    pct_rolls =
      Enum.reduce(canonical_stages(), %{}, fn s, acc ->
        Map.put(acc, :"pct_#{s.idx}", pct(Map.get(summed, s.key), leads))
      end)

    summed
    |> Map.merge(aliases)
    |> Map.merge(pct_rolls)
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
        DATE(da.first_msg_at) AS day,
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
