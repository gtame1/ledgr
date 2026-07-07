defmodule Ledgr.Domains.HelloDoctor.LifecycleMetrics do
  @moduledoc """
  HelloDoctor patient-lifecycle conversion + unit economics.

  Everything is computed at the **patient** level (conversations rolled up),
  excluding test accounts. Lifecycle tiers mirror `PatientSegments`:

    * L0 — <3 inbound messages (not a real prospect; excluded from the base)
    * L1 — ≥3 inbound messages, 0 completed consults (Engaged)
    * L2 — 1 completed consult (Converted)
    * L3 — ≥2 completed consults (Core)

  The headline metric is **L1 → L2+ conversion**: of the active base
  (L1+L2+L3), what share reached a completed consult (L2+). Denominator is the
  whole active base because L2/L3 patients were engaged before they converted.

  Sections:
    * `cohorts` — conversion by first-contact month.
    * `speed` — % of the (matured) base that converts within 30/60/90 days.
    * `buildup` — month-end stock of L1/L2/L3, reconstructed from event dates.
    * `unit_econ` — monthly Spend / Leads / CPL / New converted / CAC, joining
      `marketing_costs`.
    * `ltv` — observed net contribution per converted patient plus a projected
      LTV that values expected future (charged) return consults, using an
      observed-but-overridable return rate.

  Net contribution per consult = charged amount − Stripe fee − doctor share −
  refunds (mirrors `ConsultationRevenue`). It is currently negative on average
  (comped first consults + doctor share), which the page surfaces honestly.
  """

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting

  @return_cuts [30, 60, 90]
  # Cap on projected lifetime consults so a high assumed return rate can't blow
  # the LTV up unboundedly.
  @max_lifetime_consults 8.0

  @doc """
  Builds the full lifecycle + unit-economics report for `[start_date, end_date]`
  (month buckets in Mexico-City time). `opts[:return_rate]` overrides the
  observed return rate used by the LTV projection.
  """
  def generate(start_date, end_date, opts \\ []) do
    patients = load_patients()
    econ = consult_economics()
    spend = spend_by_month()

    months = month_range(start_date, end_date)
    today = HelloDoctor.today()

    %{
      period: {start_date, end_date},
      cohorts: cohort_rows(patients, months),
      speed: conversion_speed(patients, today),
      buildup: buildup_series(patients, months),
      unit_econ: unit_econ_rows(patients, spend, months),
      ltv: ltv_model(patients, econ, spend, months, opts),
      totals: totals(patients)
    }
  end

  @doc "Default page window: the last 6 whole months through today (MX)."
  def default_period do
    today = HelloDoctor.today()
    {today |> Date.beginning_of_month() |> months_ago(5), today}
  end

  # ── Section builders ─────────────────────────────────────────────

  # Conversion by first-contact month: engaged base vs converted (L2+).
  defp cohort_rows(patients, months) do
    engaged = Enum.filter(patients, & &1.engaged?)
    by_month = Enum.group_by(engaged, & &1.cohort_month)

    Enum.map(months, fn {y, m} = key ->
      rows = Map.get(by_month, key, [])
      base = length(rows)
      converted = Enum.count(rows, & &1.converted?)
      l3 = Enum.count(rows, &(&1.consults >= 2))
      l2 = converted - l3

      %{
        year: y,
        month: m,
        engaged: base,
        converted: converted,
        l2: l2,
        l3: l3,
        conv_pct: pct(converted, base)
      }
    end)
  end

  # Account-level conversion speed: among the base whose first contact is old
  # enough for the window to have fully elapsed (matured denominator), the share
  # that converted within N days of first contact.
  defp conversion_speed(patients, today) do
    engaged = Enum.filter(patients, & &1.engaged?)

    cuts =
      Enum.map(@return_cuts, fn n ->
        matured = Enum.filter(engaged, &(Date.diff(today, &1.first_conv) >= n))

        converted =
          Enum.count(matured, fn p ->
            p.first_completed && Date.diff(p.first_completed, p.first_conv) <= n
          end)

        %{
          days: n,
          eligible: length(matured),
          converted: converted,
          pct: pct(converted, length(matured))
        }
      end)

    %{cuts: cuts}
  end

  # Month-end stock of L1/L2/L3, reconstructed from event dates so it's true
  # point-in-time (not today's snapshot). L3 needs the 2nd-consult date.
  defp buildup_series(patients, months) do
    engaged = Enum.filter(patients, & &1.engaged?)

    Enum.map(months, fn {y, m} ->
      eom = Date.new!(y, m, 1) |> Date.end_of_month()

      engaged_by = Enum.count(engaged, &on_or_before?(&1.first_conv, eom))
      converted_by = Enum.count(engaged, &on_or_before?(&1.first_completed, eom))
      core_by = Enum.count(engaged, &on_or_before?(&1.second_completed, eom))

      %{year: y, month: m, l1: engaged_by - converted_by, l2: converted_by - core_by, l3: core_by}
    end)
  end

  # Monthly spend / leads / CPL / new-converted / CAC.
  defp unit_econ_rows(patients, spend, months) do
    engaged = Enum.filter(patients, & &1.engaged?)
    leads_by = Enum.frequencies_by(engaged, & &1.cohort_month)

    converted_by =
      engaged
      |> Enum.filter(& &1.converted?)
      |> Enum.frequencies_by(& &1.converted_month)

    Enum.map(months, fn {y, m} = key ->
      s = Map.get(spend, key, 0.0)
      leads = Map.get(leads_by, key, 0)
      converted = Map.get(converted_by, key, 0)

      %{
        year: y,
        month: m,
        spend: s,
        leads: leads,
        cpl: safe_div(s, leads),
        new_converted: converted,
        cac: safe_div(s, converted)
      }
    end)
  end

  # LTV: observed net/gross per converted, plus a forward projection that values
  # expected future (charged) return consults at the observed paid-consult net.
  defp ltv_model(patients, econ, spend, months, opts) do
    converted = Enum.filter(patients, & &1.converted?)
    n_converted = length(converted)
    n_core = Enum.count(converted, &(&1.consults >= 2))

    obs_net = sum_by(converted, & &1.net_rev)
    obs_gross = sum_by(converted, & &1.gross_rev)

    # Observed return rate P(2nd consult | had a 1st), overridable — data is thin.
    observed_r = safe_ratio(n_core, n_converted)
    r = clamp(Keyword.get(opts, :return_rate, observed_r), 0.0, 0.95)

    # Expected total lifetime consults for a converted patient (geometric), capped.
    projected_consults = min(1.0 / (1.0 - r), @max_lifetime_consults)

    # A charged consult's net is the value of a future (paid) return.
    avg_paid_net = econ.avg_net_charged

    # Forward LTV per converted: value all expected consults at the paid rate
    # (returns are charged even when the first consult was comped).
    projected_net_ltv = projected_consults * avg_paid_net

    # Blended CAC over the window: spend ÷ patients who converted in-window.
    window_spend = months |> Enum.map(&Map.get(spend, &1, 0.0)) |> Enum.sum()

    window_converted =
      converted
      |> Enum.count(fn p -> p.converted_month in months end)

    cac = safe_div(window_spend, window_converted)

    %{
      converted: n_converted,
      core: n_core,
      observed_net_per_converted: safe_div(obs_net, n_converted),
      observed_gross_per_converted: safe_div(obs_gross, n_converted),
      avg_paid_consult_net: avg_paid_net,
      observed_return_rate: observed_r,
      return_rate: r,
      return_rate_overridden?: Keyword.has_key?(opts, :return_rate),
      projected_consults: projected_consults,
      projected_net_ltv: projected_net_ltv,
      window_cac: cac,
      projected_ltv_cac: safe_div(projected_net_ltv, cac)
    }
  end

  defp totals(patients) do
    engaged = Enum.filter(patients, & &1.engaged?)
    converted = Enum.count(engaged, & &1.converted?)

    %{
      leads: length(engaged),
      converted: converted,
      conv_pct: pct(converted, length(engaged)),
      l1: Enum.count(engaged, &(&1.tier == "L1")),
      l2: Enum.count(engaged, &(&1.tier == "L2")),
      l3: Enum.count(engaged, &(&1.tier == "L3"))
    }
  end

  # ── Data loaders ─────────────────────────────────────────────────

  # One row per patient with lifecycle signals + revenue. MX-dated. Excludes
  # test accounts and test-source consults. Patients with no activity are
  # dropped. Revenue mirrors ConsultationRevenue (net = charged − fee − doctor
  # share − refunds).
  defp load_patients do
    share = ConsultationAccounting.doctor_share_sql("conv.tenant", "d.consultation_fee_mxn")
    mx = fn col -> "(#{col} AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')" end

    sql = """
    WITH msg AS (
      SELECT c.patient_id AS pid,
             MIN(c.created_at) AS first_conv,
             COUNT(*) FILTER (WHERE m.role = 'user') AS inbound
      FROM conversations c
      JOIN messages m ON m.conversation_id = c.id
      WHERE c.patient_id IS NOT NULL
      GROUP BY c.patient_id
    ),
    cons AS (
      SELECT patient_id AS pid,
             COUNT(*) AS consults,
             MIN(completed_at) AS first_completed,
             (array_agg(completed_at ORDER BY completed_at))[2] AS second_completed
      FROM consultations
      WHERE status = 'completed' AND patient_id IS NOT NULL
        AND COALESCE(payment_source, 'stripe') <> 'test'
      GROUP BY patient_id
    ),
    rev AS (
      SELECT x.pid,
             SUM(x.gross) AS gross_rev,
             SUM(x.net)   AS net_rev
      FROM (
        SELECT c.patient_id AS pid,
               COALESCE(spx.amount, c.payment_amount) AS gross,
               (COALESCE(spx.amount, c.payment_amount)
                 - COALESCE(spx.stripe_fee, 0)
                 - COALESCE(cp.doctor_share_cents / 100.0, #{share})
                 - COALESCE(spx.amount_refunded, 0)) AS net
        FROM consultations c
        LEFT JOIN conversations conv ON conv.id = c.conversation_id
        LEFT JOIN doctors d ON d.id = c.doctor_id
        LEFT JOIN LATERAL (
          SELECT sp.amount, sp.stripe_fee, sp.amount_refunded
          FROM stripe_payments sp
          WHERE sp.consultation_id = c.id
             OR (sp.consultation_id IS NULL AND c.stripe_payment_intent_id IS NOT NULL
                 AND sp.stripe_payment_intent_id = c.stripe_payment_intent_id)
          ORDER BY sp.id LIMIT 1
        ) spx ON TRUE
        LEFT JOIN consultation_payouts cp ON cp.consultation_id = c.id
        WHERE c.payment_status IN ('paid', 'confirmed', 'refunded')
          AND COALESCE(c.payment_source, 'stripe') <> 'test'
          AND c.patient_id IS NOT NULL
      ) x
      GROUP BY x.pid
    )
    SELECT p.id,
           #{mx.("msg.first_conv")}::date               AS first_conv,
           COALESCE(msg.inbound, 0)                      AS inbound,
           COALESCE(cons.consults, 0)                    AS consults,
           #{mx.("cons.first_completed")}::date          AS first_completed,
           #{mx.("cons.second_completed")}::date         AS second_completed,
           COALESCE(rev.gross_rev, 0)                    AS gross_rev,
           COALESCE(rev.net_rev, 0)                      AS net_rev
    FROM patients p
    LEFT JOIN msg  ON msg.pid = p.id
    LEFT JOIN cons ON cons.pid = p.id
    LEFT JOIN rev  ON rev.pid = p.id
    WHERE NOT (p.phone IN (#{phones_sql()}) OR p.id = '#{test_patient_id()}')
      AND (msg.pid IS NOT NULL OR cons.pid IS NOT NULL)
    """

    query(sql, [])
    |> Enum.map(&decorate_patient/1)
    # A patient with consults but no conversation row has no first_conv; skip
    # from time-bucketed views rather than crash.
    |> Enum.reject(&is_nil(&1.first_conv))
  end

  defp decorate_patient(row) do
    inbound = to_int(row.inbound)
    consults = to_int(row.consults)
    tier = tier(inbound, consults)

    %{
      patient_id: row.id,
      first_conv: row.first_conv,
      inbound: inbound,
      consults: consults,
      first_completed: row.first_completed,
      second_completed: row.second_completed,
      gross_rev: to_float(row.gross_rev),
      net_rev: to_float(row.net_rev),
      tier: tier,
      engaged?: tier in ["L1", "L2", "L3"],
      converted?: consults >= 1,
      cohort_month: {row.first_conv.year, row.first_conv.month},
      converted_month:
        row.first_completed && {row.first_completed.year, row.first_completed.month}
    }
  end

  # Global consult economics for the LTV projection.
  defp consult_economics do
    share = ConsultationAccounting.doctor_share_sql("conv.tenant", "d.consultation_fee_mxn")

    sql = """
    WITH cx AS (
      SELECT (COALESCE(spx.amount, c.payment_amount)
                - COALESCE(spx.stripe_fee, 0)
                - COALESCE(cp.doctor_share_cents / 100.0, #{share})
                - COALESCE(spx.amount_refunded, 0)) AS net,
             (COALESCE(spx.amount, c.payment_amount) > 0) AS charged
      FROM consultations c
      LEFT JOIN conversations conv ON conv.id = c.conversation_id
      LEFT JOIN doctors d ON d.id = c.doctor_id
      LEFT JOIN LATERAL (
        SELECT sp.amount, sp.stripe_fee, sp.amount_refunded
        FROM stripe_payments sp
        WHERE sp.consultation_id = c.id
           OR (sp.consultation_id IS NULL AND c.stripe_payment_intent_id IS NOT NULL
               AND sp.stripe_payment_intent_id = c.stripe_payment_intent_id)
        ORDER BY sp.id LIMIT 1
      ) spx ON TRUE
      LEFT JOIN consultation_payouts cp ON cp.consultation_id = c.id
      WHERE c.status = 'completed' AND COALESCE(c.payment_source, 'stripe') <> 'test'
        AND c.patient_id IS NOT NULL
    )
    SELECT COUNT(*) FILTER (WHERE charged) AS charged_n,
           COALESCE(SUM(net) FILTER (WHERE charged), 0) AS charged_net
    FROM cx
    """

    case query(sql, []) do
      [%{charged_n: n, charged_net: net}] ->
        n = to_int(n)
        %{charged_consults: n, avg_net_charged: safe_div(to_float(net), n)}

      _ ->
        %{charged_consults: 0, avg_net_charged: 0.0}
    end
  end

  # Marketing spend per MX month, in MXN pesos. Posted rows carry
  # spend_mxn_cents; MXN rows not yet posted fall back to `amount`.
  defp spend_by_month do
    sql = """
    SELECT (date_trunc('month', date))::date AS month_start,
           SUM(COALESCE(spend_mxn_cents, CASE WHEN currency = 'MXN' THEN round(amount * 100) ELSE 0 END)) AS mxn_cents
    FROM marketing_costs
    GROUP BY 1
    """

    query(sql, [])
    |> Enum.into(%{}, fn r ->
      {{r.month_start.year, r.month_start.month}, to_float(r.mxn_cents) / 100.0}
    end)
  rescue
    # Table may not exist yet in a fresh env — treat as no spend.
    _ -> %{}
  end

  # ── Small helpers ────────────────────────────────────────────────

  defp tier(_inbound, consults) when consults >= 2, do: "L3"
  defp tier(_inbound, consults) when consults >= 1, do: "L2"
  defp tier(inbound, _consults) when inbound >= 3, do: "L1"
  defp tier(_, _), do: "L0"

  defp on_or_before?(nil, _eom), do: false
  defp on_or_before?(%Date{} = d, eom), do: Date.compare(d, eom) != :gt

  # Inclusive list of {year, month} tuples spanning the two dates' months.
  defp month_range(start_date, end_date) do
    s = Date.beginning_of_month(start_date)
    e = Date.beginning_of_month(end_date)

    if Date.compare(s, e) == :gt do
      []
    else
      Stream.iterate(s, &(&1 |> Date.end_of_month() |> Date.add(1)))
      |> Enum.take_while(&(Date.compare(&1, e) != :gt))
      |> Enum.map(&{&1.year, &1.month})
    end
  end

  defp months_ago(date, n) when n <= 0, do: date

  defp months_ago(date, n),
    do: date |> Date.add(-1) |> Date.beginning_of_month() |> months_ago(n - 1)

  defp pct(_n, 0), do: 0.0
  defp pct(n, d), do: Float.round(n / d * 100, 1)

  defp safe_div(_n, 0), do: 0.0
  defp safe_div(_n, +0.0), do: 0.0
  defp safe_div(n, d), do: Float.round(n / d, 2)

  defp safe_ratio(_n, 0), do: 0.0
  defp safe_ratio(n, d), do: n / d

  defp clamp(v, lo, hi) when is_number(v), do: v |> max(lo) |> min(hi)
  defp clamp(_, lo, _), do: lo

  defp sum_by(list, fun), do: Enum.reduce(list, 0.0, fn x, acc -> acc + fun.(x) end)

  defp to_int(nil), do: 0
  defp to_int(n) when is_integer(n), do: n
  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_float(n), do: round(n)

  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(n) when is_float(n), do: n

  defp phones_sql, do: Ledgr.Domains.HelloDoctor.TestAccounts.phones_sql()
  defp test_patient_id, do: "2ed77952-cead-4bc4-bc44-51f5b5052d76"

  defp query(sql, params) do
    result = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, params)
    cols = Enum.map(result.columns, &String.to_atom/1)
    Enum.map(result.rows, fn row -> cols |> Enum.zip(row) |> Map.new() end)
  end
end
