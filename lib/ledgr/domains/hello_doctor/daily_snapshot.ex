defmodule Ledgr.Domains.HelloDoctor.DailySnapshot do
  @moduledoc """
  Writes `analytics_daily_snapshot` — one row per Mexico-local day of HD
  headline numbers.

  Purpose is durability, not display. The bot hard-deletes old conversations
  and messages, so counts read from the live tables are retroactively
  unreproducible; this table is Ledgr-owned and never deleted from. See
  `docs/design/reporting-architecture.md`.

  The whole computation is a single `INSERT ... SELECT ... ON CONFLICT`, so no
  values round-trip through Elixir. That is deliberate: an earlier HD worker
  silently left its table empty because `insert_all` was handed `DateTime`
  values for naive timestamp columns and the dump crash was swallowed by a
  `rescue`. With everything computed and stamped in SQL there is nothing to
  marshal and nothing to get wrong.

  Recent days are recomputed rather than written once — a consultation
  completed on Monday can have its payment confirmed on Wednesday, which
  changes Monday's row.
  """

  require Logger

  alias Ledgr.Repo

  @doc """
  Upserts snapshot rows for every day in `from..to` (inclusive, MX-local
  dates). Returns `{:ok, rows_written}`.

  Days with no activity are written as explicit zero rows, so a gap in the
  table means "the writer did not run", never "nothing happened".
  """
  def write_range(%Date{} = from, %Date{} = to) do
    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), upsert_sql(), [from, to])
    {:ok, result.num_rows}
  end

  @doc """
  Recomputes the trailing `days` days ending yesterday (MX). The default
  window covers late payment confirmations without rewriting all of history.
  """
  def refresh_recent(days \\ 7) when is_integer(days) and days > 0 do
    yesterday = Date.add(today_mx(), -1)
    write_range(Date.add(yesterday, -(days - 1)), yesterday)
  end

  @doc """
  Fills in every day from the earliest known activity up to yesterday.

  Safe to re-run: the upsert overwrites. Used on first boot, when the table
  is empty, to capture whatever history has not yet been deleted.
  """
  def backfill_all do
    case earliest_activity_date() do
      nil ->
        Logger.info("[HD DailySnapshot] no activity found — nothing to backfill")
        {:ok, 0}

      %Date{} = from ->
        to = Date.add(today_mx(), -1)

        if Date.compare(from, to) == :gt do
          {:ok, 0}
        else
          Logger.info("[HD DailySnapshot] backfilling #{from} .. #{to}")
          write_range(from, to)
        end
    end
  end

  @doc "Number of snapshot rows currently stored."
  def row_count do
    %{rows: [[n]]} =
      Ecto.Adapters.SQL.query!(Repo.active_repo(), "SELECT count(*) FROM analytics_daily_snapshot", [])

    n
  end

  @doc "Today's date in Mexico City, which is the calendar every HD report uses."
  def today_mx do
    DateTime.utc_now()
    |> DateTime.shift_zone!("America/Mexico_City")
    |> DateTime.to_date()
  end

  defp earliest_activity_date do
    sql = """
    SELECT min(d)::date FROM (
      SELECT min(assigned_at) AS d FROM consultations
      UNION ALL SELECT min(created_at) FROM conversations
      UNION ALL SELECT min(created_at) FROM patients
    ) t
    """

    case Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, []) do
      %{rows: [[%Date{} = d]]} -> d
      _ -> nil
    end
  end

  # One statement: aggregate per MX day, upsert, stamp timestamps in SQL.
  defp upsert_sql do
    """
    WITH days AS (
      SELECT generate_series($1::date, $2::date, interval '1 day')::date AS d
    ),
    cons AS (
      SELECT
        completed_at_mx                                   AS d,
        count(*)                                          AS completed,
        count(*) FILTER (WHERE is_paid)                   AS paid,
        count(*) FILTER (WHERE is_comped)                 AS comped,
        count(*) FILTER (WHERE is_refunded)               AS refunded,
        count(*) FILTER (WHERE is_collected)              AS collected,
        count(*) FILTER (WHERE is_direct)                 AS direct,
        count(*) FILTER (WHERE is_corporate)              AS corporate,
        count(DISTINCT doctor_id)                         AS doctors,
        COALESCE(sum(gross_mxn), 0)                       AS gross,
        COALESCE(sum(doctor_share_mxn), 0)                AS share,
        COALESCE(sum(hd_commission_mxn), 0)               AS commission
      FROM analytics.fct_consultation
      WHERE NOT is_test AND completed_at_mx BETWEEN $1::date AND $2::date
      GROUP BY 1
    ),
    -- Counted separately and NOT netted out of the figures above.
    cons_test AS (
      SELECT completed_at_mx AS d, count(*) AS n
      FROM analytics.fct_consultation
      WHERE is_test AND completed_at_mx BETWEEN $1::date AND $2::date
      GROUP BY 1
    ),
    convs AS (
      SELECT
        (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date AS d,
        count(*)                                            AS created,
        count(*) FILTER (WHERE payment_confirmed_at IS NOT NULL) AS paid
      FROM conversations
      WHERE (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date
              BETWEEN $1::date AND $2::date
      GROUP BY 1
    ),
    msgs AS (
      SELECT
        (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date AS d,
        count(*) AS n
      FROM messages
      WHERE (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date
              BETWEEN $1::date AND $2::date
      GROUP BY 1
    ),
    pats AS (
      SELECT
        (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date AS d,
        count(*) AS n
      FROM patients
      WHERE (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date
              BETWEEN $1::date AND $2::date
      GROUP BY 1
    )
    INSERT INTO analytics_daily_snapshot (
      snapshot_date,
      consults_completed, consults_paid, consults_comped, consults_refunded,
      consults_collected, consults_direct, consults_corporate, consults_test,
      doctors_active,
      gross_mxn, doctor_share_mxn, hd_commission_mxn,
      conversations_created, conversations_paid, messages_sent, patients_created,
      breakdowns,
      computed_at, inserted_at, updated_at
    )
    SELECT
      days.d,
      COALESCE(cons.completed, 0), COALESCE(cons.paid, 0),
      COALESCE(cons.comped, 0), COALESCE(cons.refunded, 0),
      COALESCE(cons.collected, 0), COALESCE(cons.direct, 0),
      COALESCE(cons.corporate, 0), COALESCE(cons_test.n, 0),
      COALESCE(cons.doctors, 0),
      COALESCE(cons.gross, 0), COALESCE(cons.share, 0), COALESCE(cons.commission, 0),
      COALESCE(convs.created, 0), COALESCE(convs.paid, 0),
      COALESCE(msgs.n, 0), COALESCE(pats.n, 0),
      jsonb_build_object(
        'consults_by_payment_status', COALESCE((
          SELECT jsonb_object_agg(payment_status, n) FROM (
            SELECT payment_status, count(*) AS n
            FROM analytics.fct_consultation f
            WHERE NOT f.is_test AND f.completed_at_mx = days.d
            GROUP BY 1) t), '{}'::jsonb),
        'consults_by_type', COALESCE((
          SELECT jsonb_object_agg(COALESCE(consultation_type, 'unknown'), n) FROM (
            SELECT consultation_type, count(*) AS n
            FROM analytics.fct_consultation f
            WHERE NOT f.is_test AND f.completed_at_mx = days.d
            GROUP BY 1) t), '{}'::jsonb),
        'consults_by_tenant', COALESCE((
          SELECT jsonb_object_agg(COALESCE(tenant, 'unknown'), n) FROM (
            SELECT tenant, count(*) AS n
            FROM analytics.fct_consultation f
            WHERE NOT f.is_test AND f.completed_at_mx = days.d
            GROUP BY 1) t), '{}'::jsonb),
        'conversations_by_funnel_stage', COALESCE((
          SELECT jsonb_object_agg(COALESCE(funnel_stage, 'unknown'), n) FROM (
            SELECT funnel_stage, count(*) AS n
            FROM conversations cv
            WHERE (cv.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date = days.d
            GROUP BY 1) t), '{}'::jsonb)
      ),
      timezone('utc', now())::timestamp,
      timezone('utc', now())::timestamp,
      timezone('utc', now())::timestamp
    FROM days
    LEFT JOIN cons      ON cons.d      = days.d
    LEFT JOIN cons_test ON cons_test.d = days.d
    LEFT JOIN convs     ON convs.d     = days.d
    LEFT JOIN msgs      ON msgs.d      = days.d
    LEFT JOIN pats      ON pats.d      = days.d
    ON CONFLICT (snapshot_date) DO UPDATE SET
      consults_completed    = EXCLUDED.consults_completed,
      consults_paid         = EXCLUDED.consults_paid,
      consults_comped       = EXCLUDED.consults_comped,
      consults_refunded     = EXCLUDED.consults_refunded,
      consults_collected    = EXCLUDED.consults_collected,
      consults_direct       = EXCLUDED.consults_direct,
      consults_corporate    = EXCLUDED.consults_corporate,
      consults_test         = EXCLUDED.consults_test,
      doctors_active        = EXCLUDED.doctors_active,
      gross_mxn             = EXCLUDED.gross_mxn,
      doctor_share_mxn      = EXCLUDED.doctor_share_mxn,
      hd_commission_mxn     = EXCLUDED.hd_commission_mxn,
      conversations_created = EXCLUDED.conversations_created,
      conversations_paid    = EXCLUDED.conversations_paid,
      messages_sent         = EXCLUDED.messages_sent,
      patients_created      = EXCLUDED.patients_created,
      breakdowns            = EXCLUDED.breakdowns,
      computed_at           = EXCLUDED.computed_at,
      updated_at            = EXCLUDED.updated_at
    """
  end
end
