defmodule Ledgr.Domains.HelloDoctor.Experiments do
  @moduledoc """
  Read-only tracker for Hello Doctor A/B experiments (the "Scientist"
  framework). Each experiment is pre-registered in the bot repo under
  `.claude/experiments/`; this module mirrors that registry as a machine
  contract for the Ledgr experiments page and runs the per-arm readout
  queries against the shared HD database.

  The readout SQL is a direct port of the bot's
  `scripts/metrics/experiment.sql` (four blocks: SRM, primary funnel reach,
  guardrail, and the lagging repeat-consultation curve), parameterized by
  `experiment_id`. Reporting only — no writes.

  Adding an experiment: append an entry to `@registry` (keep the `id` in sync
  with the bot's `app/services/experiments.py` registry + the pre-registration
  markdown). The readout blocks are generic, so nothing else changes.

  Data model (all in the bot-owned HD DB):

    * `experiment_assignments` — one row per (experiment, patient) enrollment:
      `experiment_id, patient_id, variant, tenant, enrolled_at`. Created by the
      bot the first time an experiment enrolls a patient; until then the table
      may not exist, and this module reports `:not_launched` gracefully.
    * `conversations.funnel_stage` — furthest funnel stage reached (mapped to an
      ordinal below).
    * `policing_events` — safety guardrail signal (`conv_id`, `severity`).
    * `consultations` — one row per consultation (`patient_id`, `completed_at`);
      source for the repeat-consultation curve. A consult "happened" when
      `completed_at IS NOT NULL`.
  """

  require Logger
  alias Ledgr.Repo

  # Funnel stage → ordinal, mirroring experiment.sql. "reached X" = ord >= X.
  @stage_order [
    {"greeting", 0},
    {"symptoms", 1},
    {"orientation", 2},
    {"doctor_recommended", 3},
    {"consultation_type", 4},
    {"consultation_type_set", 5},
    {"payment_link_sent", 6},
    {"payment_confirmed", 7},
    {"data_collected", 8},
    {"doctor_search", 9},
    {"doctor_connected", 10},
    {"consultation_complete", 11},
    {"consultation_failed", 12}
  ]

  # ── Fallback registry ───────────────────────────────────────────
  # Used only when the bot hasn't published a live `experiment_definitions`
  # row for an experiment yet (e.g. before the bot's registry-sync ships, or
  # for a dark experiment the DB doesn't carry). The live DB table is the
  # source of truth when present; see `list_experiments/0`. Newest first.
  @fallback_registry [
    %{
      id: "EXP-001-free-first-consult",
      name: "Free first consultation → repeat usage",
      status: :dark,
      status_label: "Registered · DARK (treatment not built, not launched)",
      owner: "gtame",
      registered: ~D[2026-07-01],
      launched: nil,
      horizon: "8-week run (soft target ~50 free redemptions)",
      tenants: ["mvp"],
      split: "50/50, patient-level, MVP only — assignment frozen at first contact",
      hypothesis:
        "Letting a patient experience the real product — a human doctor — once for " <>
          "free lets them feel the value orientation alone can't convey, and that " <>
          "experience drives them back to pay for a second consultation. Falsifiable: " <>
          "if the treatment arm's 2nd-consult return isn't higher than control's at the " <>
          "30-day cut, the \"sampling drives repeat paid usage\" story is wrong.",
      arms: [
        %{name: "control", description: "Patient pays for their first consultation as normal."},
        %{
          name: "treatment",
          description:
            "First consultation is free via the courtesy-comp payment bypass " <>
              "(payment_source=\"experiment\"). Same doctor flow, a comped $0 charge; the " <>
              "doctor is still paid. The patient is explicitly told the first consult is on us."
        }
      ],
      primary_metric:
        "Kaplan-Meier cumulative incidence of a 2nd consultation, per arm, among " <>
          "first-consult havers. Cuts at 15/30/45/60/90 days; the 30-day cut is the " <>
          "pre-committed decision point. Pilot: directional by design (throughput-bound, " <>
          "~85/arm needed for significance).",
      guardrails: [
        "Safety (mandatory): policing CRITICAL rate must not rise in treatment; opt-out / block signals must not rise.",
        "Payment-gate integrity: the free consult is granted ONLY through the sanctioned $0 comp bypass; the gate is unchanged."
      ],
      decision_rule: [
        {"Promote",
         "KM return curve shows a consistent, meaningful treatment > control separation at 30d, AND no guardrail regression, AND the comp mechanism + doctor flow proved out operationally."},
        {"Kill", "Any guardrail regression, OR treatment return ≤ control."},
        {"Inconclusive",
         "Run ends with curves indistinguishable — keep the measured base rate to size a future test."}
      ]
    }
  ]

  @doc """
  All experiments to show, newest-registered first. Merges three sources so
  new experiments import automatically, by precedence:

    1. **Live** — rows the bot publishes to `experiment_definitions` in the
       shared DB (source of truth; includes pre-launch/dark ones).
    2. **Fallback** — the hardcoded `@fallback_registry` for any id the DB
       doesn't carry (keeps Ledgr working before the bot's sync ships).
    3. **Discovered** — any `experiment_id` present in `experiment_assignments`
       but described by neither of the above, shown as a minimal stub so a
       launched experiment is never invisible even if its definition is missing.
  """
  def list_experiments do
    live = definitions_from_db()
    live_ids = MapSet.new(live, & &1.id)

    fallback = Enum.reject(@fallback_registry, &MapSet.member?(live_ids, &1.id))
    covered = MapSet.union(live_ids, MapSet.new(fallback, & &1.id))

    enrolled = enrollment_starts()

    discovered =
      enrolled
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(covered, &1))
      |> Enum.map(&stub_experiment(&1, enrolled[&1]))

    (live ++ fallback ++ discovered)
    |> Enum.map(&mark_enrolling(&1, enrolled))
    |> Enum.sort_by(&(&1[:registered] || ~D[1970-01-01]), {:desc, Date})
  end

  # An experiment with real enrollments is live, full stop — even if its
  # published `experiment_definitions` row still says "dark" (the bot flips
  # status / launched_at out of band, and that update can lag the first
  # enrollment). Reflect reality so an actively-enrolling experiment is never
  # mislabeled "not launched": bump the badge to running and backfill the launch
  # date from the first enrollment when the definition hasn't set one. The
  # readout already renders whenever assignments exist; this just fixes the meta.
  defp mark_enrolling(%{status: :dark, id: id} = exp, enrolled) do
    case Map.fetch(enrolled, id) do
      {:ok, started} ->
        %{
          exp
          | status: :running,
            status_label: "Running · enrolling (definition not yet updated)",
            launched: exp.launched || started
        }

      :error ->
        exp
    end
  end

  defp mark_enrolling(exp, _enrolled), do: exp

  @doc "Fetch one experiment (same precedence as `list_experiments/0`), or nil."
  def get_experiment(id), do: Enum.find(list_experiments(), &(&1.id == id))

  # ── Source 1: live definitions the bot publishes ────────────────

  defp definitions_from_db do
    if table_exists?("experiment_definitions") do
      "SELECT id, name, status, owner, registered_at, launched_at, horizon, split, tenants, hypothesis, primary_metric, arms, guardrails, decision_rule FROM experiment_definitions"
      |> query([])
      |> Enum.map(&from_db_row/1)
    else
      []
    end
  rescue
    e ->
      Logger.warning("[HD Experiments] failed reading experiment_definitions: #{inspect(e)}")
      []
  end

  # Map a DB row (bot stores list/object fields as JSON text) to the display
  # shape the page expects. Tolerant of nulls / older rows missing columns.
  defp from_db_row(row) do
    %{
      id: row.id,
      name: row.name || row.id,
      status: parse_status(row[:status]),
      status_label: row[:status] || "—",
      owner: row[:owner],
      registered: parse_date(row[:registered_at]),
      launched: parse_date(row[:launched_at]),
      horizon: row[:horizon],
      tenants: parse_json_list(row[:tenants]),
      split: row[:split],
      hypothesis: row[:hypothesis],
      primary_metric: row[:primary_metric],
      arms: parse_arms(row[:arms]),
      guardrails: parse_json_list(row[:guardrails]),
      decision_rule: parse_decision_rule(row[:decision_rule])
    }
  end

  # ── Source 3: ids seen in the wild (enrolled), with first-enroll date ────

  # Map of experiment_id => first-enrollment Date, one entry per experiment that
  # has any assignments. Powers both the "discovered" stub source and the
  # enrolling status/launch-date override for definitions that lag reality.
  defp enrollment_starts do
    if table_exists?("experiment_assignments") do
      "SELECT experiment_id, min(enrolled_at) AS first_enrolled FROM experiment_assignments GROUP BY experiment_id"
      |> query([])
      |> Enum.reject(&is_nil(&1.experiment_id))
      |> Map.new(fn row -> {row.experiment_id, parse_date(row.first_enrolled)} end)
    else
      %{}
    end
  rescue
    _ -> %{}
  end

  defp stub_experiment(id, launched) do
    %{
      id: id,
      name: id,
      status: :running,
      status_label: "Enrolling (no published definition)",
      owner: nil,
      registered: nil,
      launched: launched,
      horizon: nil,
      tenants: [],
      split: nil,
      hypothesis:
        "This experiment is enrolling patients but its definition hasn't been published to " <>
          "experiment_definitions yet. The readout below is live; the spec will fill in once " <>
          "the bot syncs its registry.",
      primary_metric: nil,
      arms: [],
      guardrails: [],
      decision_rule: []
    }
  end

  # ── JSON / value parsing helpers (bot stores JSON as text) ──────

  defp parse_status(s) when is_binary(s) do
    case String.downcase(s) do
      "dark" <> _ -> :dark
      "running" -> :running
      "concluded" -> :concluded
      _ -> :running
    end
  end

  defp parse_status(_), do: :running

  defp parse_date(%Date{} = d), do: d
  defp parse_date(%NaiveDateTime{} = dt), do: NaiveDateTime.to_date(dt)
  defp parse_date(%DateTime{} = dt), do: DateTime.to_date(dt)

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(String.slice(s, 0, 10)) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  # Accepts a JSON array string, a Postgres text[] (already a list), or nil.
  defp parse_json_list(list) when is_list(list), do: list

  defp parse_json_list(s) when is_binary(s) do
    case Jason.decode(s) do
      {:ok, list} when is_list(list) -> list
      _ -> String.split(s, ",", trim: true) |> Enum.map(&String.trim/1)
    end
  end

  defp parse_json_list(_), do: []

  # Arms: JSON array of {name, description} objects → list of maps with atom keys.
  defp parse_arms(s) when is_binary(s) do
    case Jason.decode(s) do
      {:ok, arms} when is_list(arms) ->
        Enum.map(arms, fn a ->
          %{name: a["name"] || a["arm"] || "", description: a["description"] || a["desc"] || ""}
        end)

      _ ->
        []
    end
  end

  defp parse_arms(arms) when is_list(arms), do: arms
  defp parse_arms(_), do: []

  # Decision rule: JSON array of {verdict, rule} (objects or 2-tuples) → tuples.
  defp parse_decision_rule(s) when is_binary(s) do
    case Jason.decode(s) do
      {:ok, rules} when is_list(rules) ->
        Enum.map(rules, fn
          %{"verdict" => v, "rule" => r} -> {v, r}
          [v, r] -> {v, r}
          other -> {"", to_string(other)}
        end)

      _ ->
        []
    end
  end

  defp parse_decision_rule(rules) when is_list(rules), do: rules
  defp parse_decision_rule(_), do: []

  @doc """
  Runs the four per-arm readout blocks for `experiment_id`. Returns

      {:ok, %{srm: [...], funnel: [...], guardrail: [...], repeat: [...]}}

  or `{:not_launched, reason}` when the `experiment_assignments` table doesn't
  exist yet or the experiment has zero enrollments (dark / pre-launch).
  """
  def readout(experiment_id) do
    cond do
      not table_exists?("experiment_assignments") ->
        {:not_launched, :no_table}

      enrolled_count(experiment_id) == 0 ->
        {:not_launched, :no_enrollments}

      true ->
        {:ok,
         %{
           srm: srm(experiment_id),
           funnel: funnel_reach(experiment_id),
           guardrail: guardrail(experiment_id),
           repeat: repeat(experiment_id)
         }}
    end
  end

  # ── Block 0: existence / enrollment guards ──────────────────────

  defp table_exists?(name) do
    sql = """
    SELECT EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = $1
    ) AS exists
    """

    case query(sql, [name]) do
      [%{exists: true}] -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp enrolled_count(experiment_id) do
    sql = "SELECT count(*) AS n FROM experiment_assignments WHERE experiment_id = $1"

    case query(sql, [experiment_id]) do
      [%{n: n}] -> n
      _ -> 0
    end
  rescue
    _ -> 0
  end

  # ── Block 1: SRM check (arm sizes) ──────────────────────────────

  defp srm(experiment_id) do
    sql = """
    SELECT variant, count(*) AS enrolled
    FROM experiment_assignments
    WHERE experiment_id = $1
    GROUP BY variant ORDER BY variant
    """

    query(sql, [experiment_id])
  end

  # ── Block 2: primary + funnel reach per arm (per enrolled patient) ──

  defp funnel_reach(experiment_id) do
    stage_values =
      @stage_order
      |> Enum.map(fn {stage, ord} -> "('#{stage}', #{ord})" end)
      |> Enum.join(", ")

    sql = """
    WITH stage_order(stage, ord) AS (VALUES #{stage_values}),
    reach AS (
      SELECT ea.patient_id, ea.variant, max(COALESCE(so.ord, 0)) AS max_ord
      FROM experiment_assignments ea
      LEFT JOIN conversations c ON c.patient_id = ea.patient_id AND c.tenant = ea.tenant
      LEFT JOIN stage_order so ON so.stage = c.funnel_stage
      WHERE ea.experiment_id = $1
      GROUP BY 1, 2
    )
    SELECT variant,
           count(*)                                                          AS n,
           count(*) FILTER (WHERE max_ord >= 2)                              AS reached_orientation,
           count(*) FILTER (WHERE max_ord >= 6)                              AS reached_payment_link,
           count(*) FILTER (WHERE max_ord >= 7)                              AS reached_payment_confirmed,
           round(100.0 * count(*) FILTER (WHERE max_ord >= 2) / count(*), 1) AS pct_orientation,
           round(100.0 * count(*) FILTER (WHERE max_ord >= 7) / count(*), 1) AS pct_paid
    FROM reach GROUP BY variant ORDER BY variant
    """

    query(sql, [experiment_id])
  end

  # ── Block 3: guardrail (policing events by severity) ────────────

  defp guardrail(experiment_id) do
    sql = """
    WITH pol AS (
      SELECT ea.variant, pe.severity, ea.patient_id
      FROM experiment_assignments ea
      JOIN conversations c ON c.patient_id = ea.patient_id
      JOIN policing_events pe ON pe.conv_id = c.id
      WHERE ea.experiment_id = $1
    )
    SELECT variant, severity, count(DISTINCT patient_id) AS patients_hit
    FROM pol GROUP BY variant, severity ORDER BY variant, severity
    """

    query(sql, [experiment_id])
  end

  # ── Block 4: lagging north-star (repeat-consultation curve) ─────
  # Cumulative incidence of a 2nd consultation among first-consult havers, per
  # arm, at each horizon in @repeat_cuts. The clock runs from a patient's FIRST
  # completed consult; a consult "happened" when completed_at IS NOT NULL (the
  # same signal the dashboard uses — no payment_status gate, so a comped free
  # first consult still counts as consult #1).
  #
  # Each cut N uses a *matured at-risk denominator*: only patients whose first
  # consult is already ≥ N days old are eligible, so an immature cohort can't
  # dilute the rate (right-censoring, done simply and honestly). This is the
  # discrete-cut readout that underlies the pre-registered KM curve; the 30-day
  # cut is the decision point.
  #
  # Returns one row per (variant, cut_days):
  #   variant, cut_days, eligible (at-risk), returned, pct_returned.
  @repeat_cuts [15, 30, 45, 60, 90]

  defp repeat(experiment_id) do
    cuts_values = @repeat_cuts |> Enum.map(&"(#{&1})") |> Enum.join(", ")

    sql = """
    WITH consults AS (
      SELECT ea.variant, ea.patient_id, c.completed_at,
             row_number() OVER (PARTITION BY ea.patient_id ORDER BY c.completed_at) AS rn
      FROM experiment_assignments ea
      JOIN consultations c ON c.patient_id = ea.patient_id
      WHERE ea.experiment_id = $1 AND c.completed_at IS NOT NULL
    ),
    base AS (
      SELECT f.variant, f.patient_id,
             f.completed_at AS first_at,
             s.completed_at AS second_at
      FROM consults f
      LEFT JOIN consults s ON s.patient_id = f.patient_id AND s.rn = 2
      WHERE f.rn = 1
    ),
    cuts(days) AS (VALUES #{cuts_values})
    SELECT b.variant,
           k.days AS cut_days,
           count(*) FILTER (
             WHERE b.first_at <= (now() AT TIME ZONE 'UTC') - make_interval(days => k.days)
           ) AS eligible,
           count(*) FILTER (
             WHERE b.first_at <= (now() AT TIME ZONE 'UTC') - make_interval(days => k.days)
               AND b.second_at IS NOT NULL
               AND b.second_at <= b.first_at + make_interval(days => k.days)
           ) AS returned,
           round(
             100.0 * count(*) FILTER (
               WHERE b.first_at <= (now() AT TIME ZONE 'UTC') - make_interval(days => k.days)
                 AND b.second_at IS NOT NULL
                 AND b.second_at <= b.first_at + make_interval(days => k.days)
             ) / NULLIF(count(*) FILTER (
               WHERE b.first_at <= (now() AT TIME ZONE 'UTC') - make_interval(days => k.days)
             ), 0), 1
           ) AS pct_returned
    FROM base b
    CROSS JOIN cuts k
    GROUP BY b.variant, k.days
    ORDER BY b.variant, k.days
    """

    query(sql, [experiment_id])
  end

  # ── Raw SQL helper (mirrors MonthlyReport) ──────────────────────

  defp query(sql, params) do
    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, params)
    cols = Enum.map(result.columns, &String.to_atom/1)
    Enum.map(result.rows, fn row -> cols |> Enum.zip(row) |> Map.new() end)
  end
end
