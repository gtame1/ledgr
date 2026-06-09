defmodule Ledgr.Domains.HelloDoctor.AcquisitionMetrics do
  @moduledoc """
  Per-campaign acquisition funnel + daily lead trend for the HelloDoctor
  Meta ad attribution dashboard.

  Drives off a CTE that picks each conversation's first user message,
  applies the emoji+phrase detection from `Campaigns.detection_case_sql/1`,
  then joins through to consultations / stripe_payments for the
  downstream funnel + revenue numbers.

  Attribution is content-based (emoji + phrase in the first user
  message), so it does NOT filter on `conversations.tenant`. Many
  ad-driven patients end up in `tenant = 'direct'` because the bot
  routes anything not explicitly tagged as MVP into the direct
  pipe — even when there's no DR-XXXX code (those get stuck in
  `awaiting_code`, which the dashboard surfaces as a funnel-leak
  warning).

  DR-XXXX referral_link clicks (the per-doctor wa.me from the
  doctor show page) are excluded explicitly — they're a separate
  acquisition path, not ad-attributable.

  Date range filters on `first_message_at` — the moment the patient
  hit the WhatsApp click-to-chat.
  """

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Campaigns

  @doc "Default period: last 30 days inclusive, in Mexico City time."
  def last_30_days do
    today = Ledgr.Domains.HelloDoctor.today()
    {Date.add(today, -29), today}
  end

  @doc """
  Returns `%{period, totals, per_campaign, daily}` for the date range.

    * `per_campaign` — list of maps keyed by campaign id (in PDF order),
      with: `leads`, `unique_patients`, `triaged`, `doctor_matched`,
      `paid`, `completed`, `revenue_mxn`, conversion rates.
    * `daily` — list of `%{date, by_campaign: %{id => leads}, total}`
      rows for the trend chart.
    * `totals` — sum across campaigns.

  Unattributed conversations (no campaign emoji) are NOT counted —
  this dashboard is strictly the ad-attributed funnel.
  """
  def generate(start_date, end_date) do
    start_naive = NaiveDateTime.new!(start_date, ~T[00:00:00])
    end_naive = NaiveDateTime.new!(end_date, ~T[23:59:59])

    rows = run_funnel_query(start_naive, end_naive)
    daily = run_daily_query(start_naive, end_naive)

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

  defp run_funnel_query(start_naive, end_naive) do
    detection = Campaigns.detection_case_sql("fm.content")

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
    attributed AS (
      SELECT
        fm.conversation_id,
        fm.first_msg_at,
        c.patient_id,
        c.funnel_stage,
        c.tenant,
        #{detection} AS campaign_id
      FROM first_msg fm
      JOIN conversations c ON c.id = fm.conversation_id
      WHERE fm.first_msg_at BETWEEN $1 AND $2
        -- DR-XXXX referral_link clicks (per-doctor wa.me from the doctor
        -- show page) aren't ad-attributable. Same prefix the bot uses.
        AND fm.content NOT ILIKE '%mi doctor: dr-%'
    )
    SELECT
      a.campaign_id,
      COUNT(*) AS leads,
      COUNT(DISTINCT a.patient_id) AS unique_patients,
      COUNT(*) FILTER (
        WHERE a.funnel_stage IN ('doctor_recommended','doctor_assigned','consultation_active','completed')
      ) AS triaged,
      COUNT(*) FILTER (
        WHERE a.funnel_stage IN ('doctor_assigned','consultation_active','completed')
      ) AS doctor_matched,
      -- Funnel-leak: ad clicks stuck in the bot's direct-pipe awaiting_code
      -- with no DR-XXXX code on file. The bot's routing doesn't know what
      -- to do with these; they hang.
      COUNT(*) FILTER (
        WHERE a.tenant = 'direct' AND a.funnel_stage = 'awaiting_code'
      ) AS stuck_in_awaiting_code,
      COUNT(DISTINCT cons.id) FILTER (
        WHERE cons.payment_status IN ('paid','confirmed')
      ) AS paid,
      COUNT(DISTINCT cons.id) FILTER (WHERE cons.status = 'completed') AS completed,
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

    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [start_naive, end_naive])

    columns = Enum.map(result.columns, &String.to_atom/1)

    result.rows
    |> Enum.map(fn row -> columns |> Enum.zip(row) |> Map.new() end)
    |> Enum.into(%{}, fn row -> {row.campaign_id, row} end)
  end

  defp empty_row do
    %{
      leads: 0,
      unique_patients: 0,
      triaged: 0,
      doctor_matched: 0,
      stuck_in_awaiting_code: 0,
      paid: 0,
      completed: 0,
      revenue_mxn: 0
    }
  end

  defp decorate(row) do
    leads = row.leads || 0

    Map.merge(row, %{
      leads: leads,
      unique_patients: row.unique_patients || 0,
      triaged: row.triaged || 0,
      doctor_matched: row.doctor_matched || 0,
      stuck_in_awaiting_code: row[:stuck_in_awaiting_code] || 0,
      paid: row.paid || 0,
      completed: row.completed || 0,
      revenue_mxn: to_float(row.revenue_mxn),
      lead_to_triage: pct(row.triaged, leads),
      lead_to_paid: pct(row.paid, leads),
      lead_to_completed: pct(row.completed, leads),
      stuck_pct: pct(row[:stuck_in_awaiting_code] || 0, leads)
    })
  end

  defp pct(_n, 0), do: 0.0
  defp pct(nil, _), do: 0.0
  defp pct(n, d), do: Float.round(n / d * 100, 1)

  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(n) when is_float(n), do: n

  defp totals(per_campaign) do
    keys = [
      :leads,
      :unique_patients,
      :triaged,
      :doctor_matched,
      :stuck_in_awaiting_code,
      :paid,
      :completed,
      :revenue_mxn
    ]

    summed =
      Enum.reduce(keys, %{}, fn k, acc ->
        sum =
          per_campaign
          |> Enum.map(&Map.get(&1, k, 0))
          |> Enum.reduce(0, fn v, s -> s + (v || 0) end)

        Map.put(acc, k, if(k == :revenue_mxn, do: Float.round(sum / 1, 2), else: sum))
      end)

    summed
    |> Map.put(:lead_to_paid, pct(summed.paid, summed.leads))
    |> Map.put(:lead_to_completed, pct(summed.completed, summed.leads))
    |> Map.put(:stuck_pct, pct(summed.stuck_in_awaiting_code, summed.leads))
  end

  # ── Daily trend ──────────────────────────────────────────────────

  defp run_daily_query(start_naive, end_naive) do
    detection = Campaigns.detection_case_sql("fm.content")

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
    attributed AS (
      SELECT
        DATE(fm.first_msg_at) AS day,
        #{detection} AS campaign_id
      FROM first_msg fm
      JOIN conversations c ON c.id = fm.conversation_id
      WHERE fm.first_msg_at BETWEEN $1 AND $2
        AND fm.content NOT ILIKE '%mi doctor: dr-%'
    )
    SELECT day, campaign_id, COUNT(*) AS leads
    FROM attributed
    WHERE campaign_id IS NOT NULL
    GROUP BY day, campaign_id
    ORDER BY day ASC, campaign_id
    """

    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [start_naive, end_naive])

    # Group into one row per calendar day, filling 0 for missing campaigns.
    raw =
      result.rows
      |> Enum.map(fn [day, campaign_id, leads] -> {day, campaign_id, leads} end)
      |> Enum.group_by(fn {day, _, _} -> day end, fn {_, c, l} -> {c, l} end)

    {start_date, end_date} =
      {NaiveDateTime.to_date(start_naive), NaiveDateTime.to_date(end_naive)}

    days = Date.range(start_date, end_date) |> Enum.to_list()

    Enum.map(days, fn day ->
      entries = Map.get(raw, day, [])
      by_campaign = Map.new(entries)
      total = entries |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      %{date: day, by_campaign: by_campaign, total: total}
    end)
  end
end
