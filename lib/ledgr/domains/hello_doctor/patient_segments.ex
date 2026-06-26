defmodule Ledgr.Domains.HelloDoctor.PatientSegments do
  @moduledoc """
  Patient lifecycle tiers (L0–L3) for HelloDoctor.

  Tiers are derived from existing data — no bot dependency:

    * **L0 Lead** — fewer than 3 inbound (patient) messages. A ping with no
      real engagement. NOT counted as a patient.
    * **L1 Engaged** — ≥3 inbound messages but no consultation yet.
    * **L2 Converted** — exactly 1 completed consultation (free consults
      count — see note).
    * **L3 Core** — ≥2 completed consultations (monetizes repeatedly).

  "Consultation" here = a `consultations` row with `status = 'completed'`
  (excluding `/prueba` test rows). Per product decision, a 100%-discount /
  free consult still counts toward L2/L3.

  The tier is computed **live** for the Ledgr UI (always current) and also
  materialized into the Ledgr-owned `patient_segments` table by
  `recompute/0` so the bot can read it. The `patients` table is bot-owned,
  hence the side table rather than a column on it.
  """

  alias Ledgr.Repo

  @test_patient_id "2ed77952-cead-4bc4-bc44-51f5b5052d76"

  @doc "Tier display metadata, ordered L0 → L3."
  def tiers do
    [
      %{key: "L0", label: "L0 Lead", short: "Lead", color: "#94a3b8", patient?: false},
      %{key: "L1", label: "L1 Engaged", short: "Engaged", color: "#0ea5e9", patient?: true},
      %{key: "L2", label: "L2 Converted", short: "Converted", color: "#16a34a", patient?: true},
      %{key: "L3", label: "L3 Core", short: "Core", color: "#7c3aed", patient?: true}
    ]
  end

  def tier_meta(key), do: Enum.find(tiers(), &(&1.key == key)) || List.first(tiers())

  # The shared CTE: one row per (non-test) patient with their inbound
  # message count, completed-consult count, and derived tier. Test patient
  # id is a constant, safe to inline.
  defp tier_cte do
    """
    patient_tiers AS (
      SELECT
        p.id AS patient_id,
        COALESCE(msg.inbound, 0)  AS inbound_messages,
        COALESCE(con.consults, 0) AS consult_count,
        CASE
          WHEN COALESCE(con.consults, 0) >= 2 THEN 'L3'
          WHEN COALESCE(con.consults, 0) >= 1 THEN 'L2'
          WHEN COALESCE(msg.inbound, 0) >= 3 THEN 'L1'
          ELSE 'L0'
        END AS tier
      FROM patients p
      LEFT JOIN (
        SELECT c.patient_id AS pid, COUNT(*) AS inbound
        FROM messages m
        JOIN conversations c ON c.id = m.conversation_id
        WHERE m.role = 'user' AND c.patient_id IS NOT NULL
        GROUP BY c.patient_id
      ) msg ON msg.pid = p.id
      LEFT JOIN (
        SELECT patient_id AS pid, COUNT(*) AS consults
        FROM consultations
        WHERE status = 'completed'
          AND patient_id IS NOT NULL
          AND COALESCE(payment_source, 'stripe') <> 'test'
        GROUP BY patient_id
      ) con ON con.pid = p.id
      WHERE p.id <> '#{@test_patient_id}'
    )
    """
  end

  @doc """
  Returns `%{patient_id => %{tier, inbound_messages, consult_count}}` for
  the given patient ids (or all non-test patients when `nil`). Computed
  live.
  """
  def tiers_map(patient_ids \\ nil) do
    {where, params} =
      case patient_ids do
        nil -> {"", []}
        ids when is_list(ids) -> {"WHERE patient_id = ANY($1)", [ids]}
      end

    sql = "WITH #{tier_cte()} SELECT patient_id, tier, inbound_messages, consult_count FROM patient_tiers #{where}"

    %{rows: rows} = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, params)

    Map.new(rows, fn [pid, tier, inbound, consults] ->
      {pid, %{tier: tier, inbound_messages: inbound, consult_count: consults}}
    end)
  end

  @doc "Tier for a single patient (or nil if not found)."
  def tier_for(patient_id) when is_binary(patient_id) do
    tiers_map([patient_id]) |> Map.get(patient_id)
  end

  @doc """
  Returns `%{phone => %{tier, inbound_messages, consult_count}}` for the
  given phone numbers (live). Used by the corporate pages to tier members
  by their phone. The test patient is excluded, so its phone won't appear.
  """
  def tiers_by_phone(phones) when is_list(phones) do
    sql = """
    WITH #{tier_cte()}
    SELECT p.phone, pt.tier, pt.inbound_messages, pt.consult_count
    FROM patients p
    JOIN patient_tiers pt ON pt.patient_id = p.id
    WHERE p.phone = ANY($1)
    """

    %{rows: rows} = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [phones])

    Map.new(rows, fn [phone, tier, inbound, consults] ->
      {phone, %{tier: tier, inbound_messages: inbound, consult_count: consults}}
    end)
  end

  @doc """
  Recomputes every patient's tier and upserts it into `patient_segments`
  (the snapshot the bot reads). Returns `%{"L0" => n, ...}` counts.
  """
  def recompute do
    sql = """
    WITH #{tier_cte()}
    INSERT INTO patient_segments
      (patient_id, tier, inbound_messages, consult_count, computed_at, inserted_at, updated_at)
    SELECT patient_id, tier, inbound_messages, consult_count, NOW(), NOW(), NOW()
    FROM patient_tiers
    ON CONFLICT (patient_id) DO UPDATE SET
      tier = EXCLUDED.tier,
      inbound_messages = EXCLUDED.inbound_messages,
      consult_count = EXCLUDED.consult_count,
      computed_at = EXCLUDED.computed_at,
      updated_at = NOW()
    """

    Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [])

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo.active_repo(),
        "SELECT tier, COUNT(*) FROM patient_segments GROUP BY tier",
        []
      )

    Map.new(rows, fn [tier, n] -> {tier, n} end)
  end

  @doc """
  Per-week tier distribution, bucketed by the patient's `created_at` week
  (Mexico City). For the dashboard. Pass `nil`/`nil` for all-time.
  Returns rows newest week first: `%{week_start, l0, l1, l2, l3, patients}`
  where `patients` = L1+L2+L3 (L0 leads are not counted as patients).
  """
  def weekly_cohorts(start_date, end_date) do
    start_naive = start_date && Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive(start_date)
    end_exclusive = end_date && Ledgr.Domains.HelloDoctor.mx_day_end_utc_naive(end_date)

    sql = """
    WITH #{tier_cte()}
    SELECT
      date_trunc('week', (p.created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City'))::date AS week_start,
      COUNT(*) FILTER (WHERE pt.tier = 'L0') AS l0,
      COUNT(*) FILTER (WHERE pt.tier = 'L1') AS l1,
      COUNT(*) FILTER (WHERE pt.tier = 'L2') AS l2,
      COUNT(*) FILTER (WHERE pt.tier = 'L3') AS l3
    FROM patients p
    JOIN patient_tiers pt ON pt.patient_id = p.id
    WHERE ($1::timestamp IS NULL OR p.created_at >= $1::timestamp)
      AND ($2::timestamp IS NULL OR p.created_at < $2::timestamp)
    GROUP BY week_start
    ORDER BY week_start DESC
    """

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [start_naive, end_exclusive])

    Enum.map(rows, fn [week, l0, l1, l2, l3] ->
      decorate_counts(%{week_start: week}, l0, l1, l2, l3)
    end)
  end

  @doc """
  Current-state snapshot of the WHOLE patient base (all-time, not
  period-scoped): tier counts + converted (L2+) + conversion rate.
  Conversion rate = L2+ over everyone who pinged (incl. L0 leads).
  """
  def overall do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo.active_repo(),
        "WITH #{tier_cte()} SELECT tier, COUNT(*) FROM patient_tiers GROUP BY tier",
        []
      )

    by = Map.new(rows, fn [t, n] -> {t, n} end)
    decorate_counts(%{}, by["L0"] || 0, by["L1"] || 0, by["L2"] || 0, by["L3"] || 0)
  end

  @doc """
  Same snapshot split by acquisition channel — each patient assigned to
  ONE channel by their first conversation's tenant (`direct` / `mvp` /
  `unknown`), so a patient with both isn't double-counted. Ordered by
  total desc.
  """
  def by_channel do
    sql = """
    WITH #{tier_cte()},
    first_touch AS (
      SELECT DISTINCT ON (c.patient_id) c.patient_id AS pid, c.tenant
      FROM conversations c
      WHERE c.patient_id IS NOT NULL
      ORDER BY c.patient_id, c.created_at ASC
    )
    SELECT
      COALESCE(ft.tenant, 'unknown') AS channel,
      COUNT(*) FILTER (WHERE pt.tier = 'L0') AS l0,
      COUNT(*) FILTER (WHERE pt.tier = 'L1') AS l1,
      COUNT(*) FILTER (WHERE pt.tier = 'L2') AS l2,
      COUNT(*) FILTER (WHERE pt.tier = 'L3') AS l3
    FROM patient_tiers pt
    LEFT JOIN first_touch ft ON ft.pid = pt.patient_id
    GROUP BY channel
    """

    %{rows: rows} = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [])

    rows
    |> Enum.map(fn [channel, l0, l1, l2, l3] ->
      decorate_counts(%{channel: channel}, l0, l1, l2, l3)
    end)
    |> Enum.sort_by(& &1.total, :desc)
  end

  # Adds derived figures to a tier-count row: total (all incl. L0),
  # patients (L1+), converted (L2+), and conversion_rate (L2+ over all).
  defp decorate_counts(base, l0, l1, l2, l3) do
    total = l0 + l1 + l2 + l3

    Map.merge(base, %{
      l0: l0,
      l1: l1,
      l2: l2,
      l3: l3,
      total: total,
      patients: l1 + l2 + l3,
      converted: l2 + l3,
      conversion_rate: pct(l2 + l3, total)
    })
  end

  defp pct(_n, 0), do: 0.0
  defp pct(n, d), do: Float.round(n / d * 100, 1)
end
