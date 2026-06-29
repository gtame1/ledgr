defmodule Ledgr.Domains.HelloDoctor.ConversationFunnelExport do
  @moduledoc """
  Exports a per-conversation funnel summary as CSV. One row per conversation
  with 8 single-char checkpoint columns plus key context — same shape as the
  reference SQL that ops uses interactively in psql.

  Checkpoint legend in the data: `Y` = reached / yes, `X` = explicit no
  (e.g. patient declined), `-` = not yet / not applicable.

  Filters mirror the Conversations page (status / funnel_stage / search) so
  whatever you're looking at on screen is what downloads.

  Uses raw SQL via `Ecto.Adapters.SQL` because several joined tables
  (`policing_events`, `alert_events`, `medical_records`, `messages`) are
  bot-owned and only partially mirrored in Ecto schemas — easier to keep
  the query authoritative in one place than to maintain six schemas just
  for this report.
  """

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting
  alias Ledgr.Domains.HelloDoctor.TestAccounts

  @doc """
  Returns the CSV body as a string.

  ## Options

    * `:status` — exact match on `conversations.status` (e.g. "active", "closed")
    * `:funnel_stage` — exact match on `conversations.funnel_stage`
    * `:search` — substring match on patient name OR phone (case-insensitive)
    * `:start_date` / `:end_date` — ISO date strings (`"2026-06-01"`) or `Date`s.
      Inclusive Mexico-City calendar bounds on `conversations.created_at`
      (half-open `>= start 00:00 MX` and `< end+1 00:00 MX`, UTC-correct).
    * `:limit` — integer; OMITTED by default so the full filtered set is
      exported (no silent truncation). When given, capped at `#{50_000}`.
  """
  def to_csv(opts \\ []) do
    {sql, params} = build_query(opts)
    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, params)

    [encode_row(result.columns) | Enum.map(result.rows, &encode_row/1)]
    |> IO.iodata_to_binary()
  end

  # ── Query assembly ──────────────────────────────────────────────

  defp build_query(opts) do
    share = ConsultationAccounting.doctor_share_sql("conv.tenant", "d.consultation_fee_mxn")

    base = """
    WITH funnel_stages(stage, idx) AS (VALUES
      ('greeting',1),('symptoms',2),('orientation',3),('doctor_recommended',4),
      ('consultation_type_set',5),('payment_link_sent',6),('payment_confirmed',7),
      ('data_collected',8),('doctor_search',9),('doctor_connected',10),
      ('consultation_complete',11),('consultation_failed',12)
    ),
    last_consult AS (
      -- `patient_platform_rating` is in prod but not in the dev schema; this
      -- report doesn't render it so we don't select it.
      SELECT DISTINCT ON (conversation_id)
             conversation_id, id, doctor_id, status, accepted_at, completed_at,
             patient_rating
      FROM consultations
      ORDER BY conversation_id, assigned_at DESC
    ),
    msg_counts AS (
      SELECT conversation_id, COUNT(*) AS n FROM messages GROUP BY conversation_id
    ),
    policing_counts AS (
      SELECT conv_id,
             COUNT(*)                                      AS n,
             COUNT(*) FILTER (WHERE severity='CRITICAL')   AS crit,
             COUNT(*) FILTER (WHERE severity='WARNING')    AS warn
      FROM policing_events GROUP BY conv_id
    ),
    alert_counts AS (
      SELECT conv_id,
             COUNT(*) FILTER (WHERE level='CRITICAL' AND resolved_at IS NULL) AS open_crit
      FROM alert_events GROUP BY conv_id
    ),
    -- Revenue breakdown per billed, non-test consultation. Mirrors
    -- ConsultationRevenue; aggregated to the conversation in rev_conv below.
    rev AS (
      SELECT
        c.conversation_id AS conv_id,
        COALESCE(spx.amount, c.payment_amount)                            AS gross,
        COALESCE(spx.stripe_fee, 0)                                       AS stripe_fee,
        COALESCE(cp.doctor_share_cents / 100.0, #{share})                 AS doctor_share,
        COALESCE(spx.amount, c.payment_amount)
          - COALESCE(spx.stripe_fee, 0)
          - COALESCE(cp.doctor_share_cents / 100.0, #{share})
          - COALESCE(spx.amount_refunded, 0)                             AS hd_net
      FROM consultations c
      LEFT JOIN conversations conv ON conv.id = c.conversation_id
      LEFT JOIN doctors d ON d.id = c.doctor_id
      LEFT JOIN LATERAL (
        SELECT sp.amount, sp.stripe_fee, sp.amount_refunded
        FROM stripe_payments sp
        WHERE sp.consultation_id = c.id
           OR (sp.consultation_id IS NULL
               AND c.stripe_payment_intent_id IS NOT NULL
               AND sp.stripe_payment_intent_id = c.stripe_payment_intent_id)
        ORDER BY sp.id
        LIMIT 1
      ) spx ON TRUE
      LEFT JOIN consultation_payouts cp ON cp.consultation_id = c.id
      WHERE c.payment_status IN ('paid', 'confirmed', 'refunded')
        AND COALESCE(c.payment_source, 'stripe') <> 'test'
        AND #{TestAccounts.not_test_patient_sql("c.patient_id")}
    ),
    -- Summed across ALL of a conversation's billed consultations (matches
    -- the conversation list page), not just the last one.
    rev_conv AS (
      SELECT
        conv_id,
        SUM(gross)        AS gross,
        SUM(doctor_share) AS doctor_share,
        SUM(stripe_fee)   AS stripe_fee,
        SUM(hd_net)       AS hd_net
      FROM rev
      WHERE conv_id IS NOT NULL
      GROUP BY conv_id
    )
    SELECT
      c.id                                                                 AS conv_id,
      c.tenant                                                              AS tn,
      p.id                                                                  AS patient_id,
      left(COALESCE(p.display_name, p.full_name, '-'), 18)                  AS patient,
      -- Lifecycle tier (L0–L3) from the patient_segments snapshot.
      COALESCE(ps.tier, 'L0')                                               AS tier,
      -- New this month vs. already existed (relative to the conversation's
      -- calendar month, not "now"). Y = patient was created in the same
      -- calendar month as the conversation. - = pre-existing.
      CASE
        WHEN p.id IS NULL THEN '-'
        WHEN date_trunc('month', p.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')
           = date_trunc('month', c.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City') THEN 'Y'
        ELSE '-'
      END                                                                   AS pnew,
      p.phone                                                               AS phone,
      CASE
        WHEN p.phone IN (#{TestAccounts.phones_sql()})
        THEN 'Y' ELSE 'N'
      END                                                                   AS is_test,
      (c.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date AS created,
      date_trunc('month', c.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')::date AS month_created,
      to_char(c.last_message_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City', 'MM-DD HH24:MI') AS last_msg,
      CASE WHEN c.doctor_recommended OR fs.idx >= 4 THEN 'Y' ELSE '-' END   AS rec,
      CASE WHEN c.doctor_declined_by_patient                THEN 'X'
           WHEN c.consultation_type IS NOT NULL             THEN 'Y'
           ELSE '-' END                                                      AS acc,
      CASE WHEN fs.idx >= 6 THEN 'Y' ELSE '-' END                            AS link,
      CASE WHEN c.stripe_payment_intent_id IS NOT NULL THEN 'Y' ELSE '-' END AS paid,
      -- Promo/discount code on this conversation's payment (e.g. SALUD26),
      -- matched via the linked consultation or the shared payment intent.
      COALESCE((
        SELECT sp.discount_code FROM stripe_payments sp
        WHERE sp.discount_code IS NOT NULL
          AND (sp.consultation_id = lc.id
               OR (c.stripe_payment_intent_id IS NOT NULL
                   AND sp.stripe_payment_intent_id = c.stripe_payment_intent_id))
        LIMIT 1
      ), '-')                                                                AS disc,
      CASE WHEN c.data_review_sent_at IS NOT NULL THEN 'Y' ELSE '-' END      AS rev,
      CASE WHEN lc.id IS NOT NULL THEN 'Y' ELSE '-' END                      AS bcast,
      CASE WHEN lc.accepted_at IS NOT NULL THEN 'Y' ELSE '-' END             AS docacc,
      CASE WHEN lc.completed_at IS NOT NULL THEN 'Y' ELSE '-' END            AS done,
      c.funnel_stage                                                         AS stage,
      COALESCE(c.consultation_type, '-')                                     AS type,
      COALESCE(d.name, '-')                                                  AS doctor,
      COALESCE(left(mr.chief_complaint, 40), '-')                            AS complaint,
      COALESCE(mc.n, 0)                                                      AS msgs,
      COALESCE(pc.n, 0)                                                      AS pol,
      COALESCE(pc.crit, 0)                                                   AS pcrit,
      COALESCE(ac.open_crit, 0)                                              AS alerts,
      COALESCE(lc.patient_rating::text, '-')                                 AS rating,
      rev_conv.gross                                                         AS gross,
      rev_conv.doctor_share                                                  AS doctor_share,
      rev_conv.stripe_fee                                                    AS stripe_fee,
      rev_conv.hd_net                                                        AS hd_net
    FROM conversations c
    LEFT JOIN patients         p  ON p.id = c.patient_id
    LEFT JOIN patient_segments ps ON ps.patient_id = c.patient_id
    LEFT JOIN funnel_stages    fs ON fs.stage = c.funnel_stage
    LEFT JOIN last_consult     lc ON lc.conversation_id = c.id
    LEFT JOIN doctors          d  ON d.id = lc.doctor_id
    LEFT JOIN medical_records  mr ON mr.conversation_id = c.id
    LEFT JOIN msg_counts       mc ON mc.conversation_id = c.id
    LEFT JOIN policing_counts  pc ON pc.conv_id = c.id
    LEFT JOIN alert_counts     ac ON ac.conv_id = c.id
    LEFT JOIN rev_conv            ON rev_conv.conv_id = c.id
    """

    {where_sql, params} = build_filters(opts)

    sql =
      base <>
        where_sql <>
        " ORDER BY c.created_at DESC " <>
        limit_clause(opts)

    {sql, params}
  end

  defp build_filters(opts) do
    {clauses, params} =
      Enum.reduce(
        [
          {:status, "c.status"},
          {:funnel_stage, "c.funnel_stage"}
        ],
        {[], []},
        fn {key, column}, {acc, params} ->
          case opts[key] do
            v when v in [nil, ""] ->
              {acc, params}

            v ->
              idx = length(params) + 1
              {["#{column} = $#{idx}" | acc], params ++ [v]}
          end
        end
      )

    {clauses, params} =
      case opts[:search] do
        v when v in [nil, ""] ->
          {clauses, params}

        v ->
          term = "%#{v}%"
          name_idx = length(params) + 1
          phone_idx = name_idx + 1

          sql =
            "(p.full_name ILIKE $#{name_idx} OR p.display_name ILIKE $#{name_idx} OR p.phone ILIKE $#{phone_idx})"

          {[sql | clauses], params ++ [term, term]}
      end

    # created_at range — Mexico-City calendar dates → UTC-naive half-open
    # bounds (the only tz-safe shape; see HelloDoctor.mx_day_start_utc_naive/1).
    {clauses, params} =
      case mx_start(opts[:start_date]) do
        nil ->
          {clauses, params}

        ndt ->
          idx = length(params) + 1
          {["c.created_at >= $#{idx}" | clauses], params ++ [ndt]}
      end

    {clauses, params} =
      case mx_end(opts[:end_date]) do
        nil ->
          {clauses, params}

        ndt ->
          idx = length(params) + 1
          {["c.created_at < $#{idx}" | clauses], params ++ [ndt]}
      end

    case clauses do
      [] -> {"", params}
      _ -> {" WHERE " <> Enum.join(Enum.reverse(clauses), " AND "), params}
    end
  end

  # Parse an ISO date string (or Date) to the inclusive UTC-naive lower
  # bound; `nil`/blank/invalid → nil (no clause).
  defp mx_start(d), do: with_date(d, &HelloDoctor.mx_day_start_utc_naive/1)
  # …and the EXCLUSIVE upper bound (start of the day after `end_date`).
  defp mx_end(d), do: with_date(d, &HelloDoctor.mx_day_end_utc_naive/1)

  defp with_date(nil, _fun), do: nil
  defp with_date("", _fun), do: nil
  defp with_date(%Date{} = d, fun), do: fun.(d)

  defp with_date(str, fun) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> fun.(d)
      _ -> nil
    end
  end

  # No default limit — the full filtered set is exported so nothing is
  # silently dropped. A caller-supplied `:limit` still applies, capped here.
  @max_limit 50_000

  defp limit_clause(opts) do
    case opts[:limit] do
      v when v in [nil, ""] -> ""
      v when is_integer(v) -> " LIMIT #{min(v, @max_limit)}"
      v when is_binary(v) ->
        case Integer.parse(v) do
          {n, _} -> " LIMIT #{min(n, @max_limit)}"
          :error -> ""
        end
    end
  end

  # ── CSV encoding ────────────────────────────────────────────────

  defp encode_row(row) do
    row
    |> Enum.map(&csv_field/1)
    |> Enum.join(",")
    |> Kernel.<>("\r\n")
  end

  defp csv_field(nil), do: ""
  defp csv_field(v) when is_integer(v) or is_float(v), do: to_string(v)
  defp csv_field(%Date{} = d), do: Date.to_iso8601(d)
  defp csv_field(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp csv_field(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp csv_field(v) when is_binary(v) do
    if String.contains?(v, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(v, "\"", "\"\"")}")
    else
      v
    end
  end

  defp csv_field(other), do: csv_field(to_string(other))
end
