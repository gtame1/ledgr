defmodule Ledgr.Domains.HelloDoctor.ConsultationFunnelExport do
  @moduledoc """
  Exports a per-consultation summary as CSV — one row per consult with
  doctor / payment / fees / review / operational fields. Same shape as the
  reference SQL ops uses interactively in psql.

  Filters mirror the Consultations page (status / search) so whatever's on
  screen is what downloads.

  Uses raw SQL via `Ecto.Adapters.SQL` because several columns
  (`tenant`, `patient_platform_rating`, `doctor_rating`,
  `doctor_platform_rating`, `doctor_comment`, `doctor_ping_count`,
  `search_extended_count`) and tables (`prescriptions`,
  `consultation_calls`) are bot-owned and only partially mirrored in
  Ecto schemas. Keeping the query authoritative in one place is easier
  than maintaining the schemas just for this report.
  """

  alias Ledgr.Repo

  @doc """
  Returns the CSV body as a string.

  ## Options

    * `:status` — exact match on `consultations.status`
    * `:search` — substring match on patient name / phone / doctor name
    * `:limit` — integer; default 1000, capped at 5000
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
    WITH rx_counts AS (
      SELECT consultation_id, COUNT(*) AS n
      FROM prescriptions GROUP BY consultation_id
    ),
    call_flag AS (
      SELECT DISTINCT consultation_id, 1 AS has_call FROM consultation_calls
    )
    SELECT
      substr(cs.id, 1, 8)                                                AS consult_id,
      cs.tenant                                                          AS tn,
      cs.status                                                          AS status,
      cs.consultation_type                                                AS type,
      cs.assigned_at::date                                                AS assigned,
      to_char(cs.accepted_at, 'MM-DD HH24:MI')                            AS accepted,
      to_char(cs.completed_at, 'MM-DD HH24:MI')                           AS completed,
      cs.duration_minutes                                                 AS dur_min,
      CASE WHEN cs.accepted_at  IS NOT NULL THEN 'Y' ELSE '-' END         AS acc,
      CASE WHEN cs.completed_at IS NOT NULL THEN 'Y' ELSE '-' END         AS done,
      cs.patient_id                                                       AS patient_id,
      left(COALESCE(p.display_name, p.full_name, '-'), 16)                AS patient,
      p.phone                                                             AS phone,
      cs.doctor_id                                                        AS doctor_id,
      left(COALESCE(d.name, '-'), 22)                                     AS doctor,
      left(COALESCE(d.specialty, '-'), 18)                                AS specialty,
      cs.payment_status                                                   AS pay,
      cs.payment_amount                                                   AS amount,
      COALESCE(conv.platform_fee_amount::text, '-')                       AS plat_fee,
      COALESCE(conv.doctor_fee_amount::text, '-')                         AS doc_fee,
      COALESCE(cs.stripe_payment_intent_id, '-')                          AS stripe_pi,
      cs.doctor_ping_count                                                AS pings,
      COALESCE(jsonb_array_length(NULLIF(cs.rejected_by_doctors,'')::jsonb), 0) AS rejects,
      cs.search_extended_count                                            AS ext,
      COALESCE(rx.n, 0)                                                   AS rx,
      CASE WHEN cf.has_call = 1 THEN 'Y' ELSE '-' END                     AS vid,
      COALESCE(cs.patient_rating::text, '-')                              AS p_rate,
      COALESCE(cs.patient_platform_rating::text, '-')                     AS p_plat,
      left(COALESCE(cs.patient_comment, '-'), 30)                         AS p_comment,
      COALESCE(cs.doctor_rating::text, '-')                               AS d_rate,
      COALESCE(cs.doctor_platform_rating::text, '-')                      AS d_plat,
      left(COALESCE(cs.doctor_comment, '-'), 30)                          AS d_comment,
      cs.conversation_id                                                  AS conv_id
    FROM consultations cs
    LEFT JOIN conversations conv ON conv.id = cs.conversation_id
    LEFT JOIN patients      p    ON p.id    = cs.patient_id
    LEFT JOIN doctors       d    ON d.id    = cs.doctor_id
    LEFT JOIN rx_counts     rx   ON rx.consultation_id = cs.id
    LEFT JOIN call_flag     cf   ON cf.consultation_id = cs.id
    """

    {where_sql, params} = build_filters(opts)

    sql =
      base <>
        where_sql <>
        " ORDER BY cs.assigned_at DESC " <>
        limit_clause(opts)

    {sql, params}
  end

  defp build_filters(opts) do
    {clauses, params} =
      case opts[:status] do
        v when v in [nil, ""] -> {[], []}
        v -> {["cs.status = $1"], [v]}
      end

    {clauses, params} =
      case opts[:search] do
        v when v in [nil, ""] ->
          {clauses, params}

        v ->
          term = "%#{v}%"
          base_idx = length(params) + 1
          name_idx = base_idx
          phone_idx = base_idx + 1
          doctor_idx = base_idx + 2

          sql =
            "(p.full_name ILIKE $#{name_idx} OR p.display_name ILIKE $#{name_idx} " <>
              "OR p.phone ILIKE $#{phone_idx} OR d.name ILIKE $#{doctor_idx})"

          {[sql | clauses], params ++ [term, term, term]}
      end

    case clauses do
      [] -> {"", params}
      _ -> {" WHERE " <> Enum.join(Enum.reverse(clauses), " AND "), params}
    end
  end

  @max_limit 5000
  @default_limit 1000

  defp limit_clause(opts) do
    limit =
      case opts[:limit] do
        nil -> @default_limit
        "" -> @default_limit
        v when is_integer(v) -> min(v, @max_limit)
        v when is_binary(v) -> v |> Integer.parse() |> elem(0) |> min(@max_limit)
      end

    " LIMIT #{limit}"
  end

  # ── CSV encoding (same as ConversationFunnelExport — duplicated to keep
  # the export modules self-contained; consolidate if a third one shows up).

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
