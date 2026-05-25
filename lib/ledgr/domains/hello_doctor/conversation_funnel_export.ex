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

  @doc """
  Returns the CSV body as a string.

  ## Options

    * `:status` — exact match on `conversations.status` (e.g. "active", "closed")
    * `:funnel_stage` — exact match on `conversations.funnel_stage`
    * `:search` — substring match on patient name OR phone (case-insensitive)
    * `:limit` — integer; default `1000`, capped to keep responses bounded
  """
  def to_csv(opts \\ []) do
    {sql, params} = build_query(opts)
    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, params)

    [encode_row(result.columns) | Enum.map(result.rows, &encode_row/1)]
    |> IO.iodata_to_binary()
  end

  # ── Query assembly ──────────────────────────────────────────────

  defp build_query(opts) do
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
    )
    SELECT
      'id-' || substr(c.id, 1, 8)                                          AS conv_id,
      c.tenant                                                              AS tn,
      left(COALESCE(p.display_name, p.full_name, '-'), 18)                  AS patient,
      p.phone                                                               AS phone,
      c.created_at::date                                                    AS created,
      to_char(c.last_message_at, 'MM-DD HH24:MI')                           AS last_msg,
      CASE WHEN c.doctor_recommended OR fs.idx >= 4 THEN 'Y' ELSE '-' END   AS rec,
      CASE WHEN c.doctor_declined_by_patient                THEN 'X'
           WHEN c.consultation_type IS NOT NULL             THEN 'Y'
           ELSE '-' END                                                      AS acc,
      CASE WHEN fs.idx >= 6 THEN 'Y' ELSE '-' END                            AS link,
      CASE WHEN c.stripe_payment_intent_id IS NOT NULL THEN 'Y' ELSE '-' END AS paid,
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
      COALESCE(lc.patient_rating::text, '-')                                 AS rating
    FROM conversations c
    LEFT JOIN patients         p  ON p.id = c.patient_id
    LEFT JOIN funnel_stages    fs ON fs.stage = c.funnel_stage
    LEFT JOIN last_consult     lc ON lc.conversation_id = c.id
    LEFT JOIN doctors          d  ON d.id = lc.doctor_id
    LEFT JOIN medical_records  mr ON mr.conversation_id = c.id
    LEFT JOIN msg_counts       mc ON mc.conversation_id = c.id
    LEFT JOIN policing_counts  pc ON pc.conv_id = c.id
    LEFT JOIN alert_counts     ac ON ac.conv_id = c.id
    """

    {where_sql, params} = build_filters(opts)

    sql =
      base <>
        where_sql <>
        " ORDER BY c.created_at DESC " <>
        limit_clause(opts, params)

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

    case clauses do
      [] -> {"", params}
      _ -> {" WHERE " <> Enum.join(Enum.reverse(clauses), " AND "), params}
    end
  end

  # Cap to keep download size manageable. Re-run with a tighter filter if
  # you hit it.
  @max_limit 5000
  @default_limit 1000

  defp limit_clause(opts, params_before) do
    limit =
      case opts[:limit] do
        nil -> @default_limit
        "" -> @default_limit
        v when is_integer(v) -> min(v, @max_limit)
        v when is_binary(v) -> v |> Integer.parse() |> elem(0) |> min(@max_limit)
      end

    # Append to the params list outside this function — we use a literal
    # here since the limit is server-controlled, not user-supplied SQL.
    _ = params_before
    " LIMIT #{limit}"
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
