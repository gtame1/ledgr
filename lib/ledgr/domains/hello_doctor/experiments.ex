defmodule Ledgr.Domains.HelloDoctor.Experiments do
  @moduledoc """
  Read-only tracker for Hello Doctor A/B experiments (the "Scientist"
  framework). Each experiment is pre-registered in the bot repo under
  `.claude/experiments/`; this module mirrors that registry as a machine
  contract for the Ledgr experiments page and runs the per-arm readout
  queries against the shared HD database.

  The readout SQL is a direct port of the bot's
  `scripts/metrics/experiment.sql` (four blocks: SRM, primary funnel reach,
  guardrail, lagging retention), parameterized by `experiment_id`. Reporting
  only — no writes.

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
    * `messages` — activity for the lagging retention block.
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

  # ── Registry ────────────────────────────────────────────────────
  # Mirrors the bot's pre-registration artifacts. Newest first.
  @registry [
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
          "first-consult havers. Cuts at 15/30/60/90 days; the 30-day cut is the " <>
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

  @doc "All registered experiments, newest first."
  def list_experiments, do: @registry

  @doc "Fetch one experiment spec by id, or nil."
  def get_experiment(id), do: Enum.find(@registry, &(&1.id == id))

  @doc """
  Runs the four per-arm readout blocks for `experiment_id`. Returns

      {:ok, %{srm: [...], funnel: [...], guardrail: [...], retention: [...]}}

  or `{:not_launched, reason}` when the `experiment_assignments` table doesn't
  exist yet or the experiment has zero enrollments (dark / pre-launch).
  """
  def readout(experiment_id) do
    cond do
      not assignments_table_exists?() ->
        {:not_launched, :no_table}

      enrolled_count(experiment_id) == 0 ->
        {:not_launched, :no_enrollments}

      true ->
        {:ok,
         %{
           srm: srm(experiment_id),
           funnel: funnel_reach(experiment_id),
           guardrail: guardrail(experiment_id),
           retention: retention(experiment_id)
         }}
    end
  end

  # ── Block 0: existence / enrollment guards ──────────────────────

  defp assignments_table_exists? do
    sql = """
    SELECT EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = 'experiment_assignments'
    )
    """

    case query(sql, []) do
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

  # ── Block 4: lagging north-star (repeat usage, active on >=2 MX days) ──

  defp retention(experiment_id) do
    sql = """
    WITH days AS (
      SELECT ea.patient_id, ea.variant,
             count(DISTINCT (m.created_at AT TIME ZONE 'UTC'
                                          AT TIME ZONE 'America/Mexico_City')::date) AS active_days
      FROM experiment_assignments ea
      JOIN conversations c ON c.patient_id = ea.patient_id
      JOIN messages m ON m.conversation_id = c.id AND m.role = 'user'
      WHERE ea.experiment_id = $1
      GROUP BY 1, 2
    )
    SELECT variant,
           count(*)                                                             AS patients_with_msgs,
           count(*) FILTER (WHERE active_days >= 2)                             AS returning,
           round(100.0 * count(*) FILTER (WHERE active_days >= 2) / count(*), 1) AS pct_returning
    FROM days GROUP BY variant ORDER BY variant
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
