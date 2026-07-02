defmodule Ledgr.Domains.HelloDoctor.Nps do
  @moduledoc """
  Read model for the NPS (Net Promoter Score) tracker page.

  Reads the bot-owned `nps_responses` table (a survey per completed
  consultation: `status` walks `pending_q1 → … → completed`; `score` 0–10 is
  the Q1 answer, `comment` the Q2 answer). No Ecto schema — raw SQL like the
  other HD report read-models.

  NPS bucketing (standard): promoter 9–10, passive 7–8, detractor 0–6.
  `NPS = %promoters − %detractors` over *answered* surveys (score present).
  """

  alias Ledgr.Repo

  # UTC → Mexico City for date display/bucketing (created_at is UTC-naive).
  @mx "AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City'"

  @doc """
  Headline NPS metrics (no per-response list) — cheap enough for the main
  dashboard. All-time.
  """
  def summary do
    totals = totals()

    %{
      nps: nps_score(totals),
      total: totals.total,
      sent: totals.sent,
      answered: totals.answered,
      promoters: totals.promoters,
      passives: totals.passives,
      detractors: totals.detractors,
      avg_score: totals.avg_score,
      response_rate: pct(totals.answered, totals.sent),
      promoter_pct: pct(totals.promoters, totals.answered),
      passive_pct: pct(totals.passives, totals.answered),
      detractor_pct: pct(totals.detractors, totals.answered)
    }
  end

  @doc "Everything the NPS page needs, in one bundle."
  def overview do
    Map.merge(summary(), %{
      score_dist: score_distribution(),
      by_status: by_status(),
      responses: responses()
    })
  end

  defp totals do
    %{rows: [row]} =
      query("""
      SELECT
        COUNT(*)                                                    AS total,
        COUNT(*) FILTER (WHERE sent_at IS NOT NULL)                 AS sent,
        COUNT(*) FILTER (WHERE score IS NOT NULL)                   AS answered,
        COUNT(*) FILTER (WHERE score >= 9)                          AS promoters,
        COUNT(*) FILTER (WHERE score BETWEEN 7 AND 8)               AS passives,
        COUNT(*) FILTER (WHERE score IS NOT NULL AND score <= 6)    AS detractors,
        COALESCE(ROUND(AVG(score)::numeric, 1), 0)                  AS avg_score
      FROM nps_responses
      """)

    [total, sent, answered, promoters, passives, detractors, avg_score] = row

    %{
      total: total,
      sent: sent,
      answered: answered,
      promoters: promoters,
      passives: passives,
      detractors: detractors,
      avg_score: to_float(avg_score)
    }
  end

  # NPS = %promoters − %detractors, rounded; nil when nothing's answered yet.
  defp nps_score(%{answered: 0}), do: nil

  defp nps_score(%{answered: a, promoters: p, detractors: d}) do
    round((p - d) / a * 100)
  end

  # Counts per score 0..10, zero-filled so the chart has every bucket.
  defp score_distribution do
    %{rows: rows} =
      query(
        "SELECT score, COUNT(*) FROM nps_responses WHERE score IS NOT NULL GROUP BY score"
      )

    counts = Map.new(rows, fn [s, n] -> {s, n} end)
    Enum.map(0..10, fn s -> %{score: s, count: Map.get(counts, s, 0)} end)
  end

  defp by_status do
    %{rows: rows} =
      query("SELECT status, COUNT(*) FROM nps_responses GROUP BY status ORDER BY COUNT(*) DESC")

    Enum.map(rows, fn [status, n] -> %{status: status, count: n} end)
  end

  # Individual responses, newest first. Answered ones surface first within
  # the ordering via answered_q1_at, but we sort by creation for a stable list.
  defp responses do
    %{rows: rows} =
      query("""
      SELECT
        n.id,
        COALESCE(p.display_name, p.full_name, '—')  AS patient,
        n.tenant,
        n.score,
        n.classification,
        n.comment,
        n.status,
        n.cancellation_reason,
        (n.created_at #{@mx})::date                 AS created,
        (n.answered_q1_at #{@mx})::date             AS answered_on,
        n.conv_id
      FROM nps_responses n
      LEFT JOIN patients p ON p.id = n.patient_id
      ORDER BY n.created_at DESC
      LIMIT 1000
      """)

    Enum.map(rows, fn [id, patient, tenant, score, cls, comment, status, cancel, created, answered_on, conv_id] ->
      %{
        id: id,
        patient: patient,
        tenant: tenant,
        score: score,
        classification: cls || classify(score),
        comment: comment,
        status: status,
        cancellation_reason: cancel,
        created: created,
        answered_on: answered_on,
        conv_id: conv_id
      }
    end)
  end

  @doc "Standard NPS bucket for a 0–10 score (nil when unscored)."
  def classify(nil), do: nil
  def classify(s) when s >= 9, do: "promoter"
  def classify(s) when s >= 7, do: "passive"
  def classify(_), do: "detractor"

  defp query(sql), do: Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [])

  defp pct(_n, 0), do: 0.0
  defp pct(_n, nil), do: 0.0
  defp pct(n, d), do: Float.round(n / d * 100, 1)

  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(n) when is_float(n), do: n
end
