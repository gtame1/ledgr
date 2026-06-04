defmodule Ledgr.Domains.AumentaMiPension.TraspasoCoverage do
  @moduledoc """
  Data-quality + eligibility metrics for the AFORE *traspaso* requirements.

  Measures, across the unified "lead" universe (a distinct person keyed
  by normalized 10-digit phone, unioned from `customers`,
  `checkup_responses`, `calculadora_submissions` and `pension_cases`
  joined back to `customers`), how many leads carry each field needed to
  start an AFORE transfer, plus pension-eligibility signals.

  Traspaso requisites:

    1. Current AFORE                  → `checkup_responses.afore_name` / `has_afore`
    2. Last AFORE change > 1 year ago → NOT captured anywhere (no field)
    3. NSS + CURP (for validation)    → `customers` + `checkup_responses`
    4. Not on the exclusion list      → NOT captured anywhere (no field)
    5. Comprobante de domicilio + ID  → no structured field; loose proxy is
                                         `pension_cases.media_analyses`

  Eligibility signals:

    * age > 60          → `date_of_birth` / `contact_birth_date` / `birth_date` / `pension_cases.age`
    * weeks > 850       → max `weeks_contributed` across customers / checkup / pension_cases
    * 1+ yr inactive    → last contribution > 1 year (`last_imss_contribution_date`,
                          checkup `last_year_cotized`; `"working"` = active)
    * employment status → free-text `current_employment_status` classified as
                          inactive (baja / no cotiza / desempleado / jubilado / …)

  Everything is computed live from the bot-shared Postgres on each call.
  Phone normalization mirrors `Phones.normalize/1` enough for counting:
  strip non-digits, take the last 10. Cheap at lead counts in the
  low thousands; revisit with an expression index if it gets slow.
  """

  alias Ledgr.Repo

  # Case-insensitive regex marking an employment-status string as "not
  # currently contributing/working" (incl. retired). The text is messy
  # free-form, so this is a heuristic, not authoritative.
  @emp_inactive_re "(no trab|no cotiz|no est|baja|desemple|sin trab|sin cotiz|not_work|jubilad|pensionad)"

  # Source tables that make up a lead, in CSV column order. Each lead row
  # takes the *latest* record per source (per normalized phone). `join` is
  # "" for tables that carry the phone directly, or a JOIN onto
  # `customers c` for tables that reference it via `customer_id`.
  @export_sources [
    %{prefix: "customers", table: "customers", phone: "t.phone", join: ""},
    %{prefix: "checkup", table: "checkup_responses", phone: "t.contact_phone", join: ""},
    %{prefix: "calculadora", table: "calculadora_submissions", phone: "t.contact_phone", join: ""},
    %{
      prefix: "pension_case",
      table: "pension_cases",
      phone: "c.phone",
      join: "JOIN customers c ON t.customer_id = c.id"
    },
    %{
      prefix: "conversation",
      table: "conversations",
      phone: "c.phone",
      join: "JOIN customers c ON t.customer_id = c.id"
    },
    %{prefix: "crm", table: "lead_crm", phone: "t.phone", join: ""}
  ]

  # Preferred "latest row" tiebreaker columns, best first.
  @order_pref ~w(last_message_at updated_at created_at inserted_at)

  @doc """
  Returns the full coverage + eligibility snapshot as a map.
  """
  def coverage do
    [
      [
        total,
        with_nss,
        with_curp,
        with_afore,
        nss_and_curp,
        all_three,
        over_60,
        age_known,
        weeks_over_850,
        weeks_known,
        inactive_1yr,
        activity_known,
        emp_inactive,
        emp_known
      ]
    ] =
      query!("WITH #{norm_cte()},
      leads AS (
        SELECT p,
               bool_or(nss IS NOT NULL)  AS has_nss,
               bool_or(curp IS NOT NULL) AS has_curp,
               bool_or(afore IS NOT NULL) AS has_afore,
               greatest(max(age_int), max(extract(year from age(current_date, birth))::int)) AS age,
               max(weeks) AS weeks,
               max(activity) AS last_activity,
               bool_or(emp ~* '#{@emp_inactive_re}') AS emp_inactive,
               bool_or(emp IS NOT NULL) AS emp_known
        FROM norm WHERE p <> '' AND length(p) = 10 GROUP BY p
      )
      SELECT count(*),
             count(*) FILTER (WHERE has_nss),
             count(*) FILTER (WHERE has_curp),
             count(*) FILTER (WHERE has_afore),
             count(*) FILTER (WHERE has_nss AND has_curp),
             count(*) FILTER (WHERE has_nss AND has_curp AND has_afore),
             count(*) FILTER (WHERE age > 60),
             count(*) FILTER (WHERE age IS NOT NULL),
             count(*) FILTER (WHERE weeks > 850),
             count(*) FILTER (WHERE weeks IS NOT NULL),
             count(*) FILTER (WHERE last_activity < current_date - interval '1 year'),
             count(*) FILTER (WHERE last_activity IS NOT NULL),
             count(*) FILTER (WHERE emp_inactive),
             count(*) FILTER (WHERE emp_known)
      FROM leads")

    [[total_cases, media_cases]] =
      query!("""
      SELECT count(*), count(*) FILTER (WHERE nullif(media_analyses,'') IS NOT NULL)
      FROM pension_cases
      """)

    afore =
      query!("""
      SELECT afore_name, count(*) FROM checkup_responses
      WHERE nullif(afore_name,'') IS NOT NULL
      GROUP BY afore_name ORDER BY count(*) DESC, afore_name
      """)
      |> Enum.map(fn [name, count] -> %{name: name, count: count} end)

    sources =
      query!("""
      SELECT 'customers', count(*), count(phone), count(nss), count(curp) FROM customers
      UNION ALL
      SELECT 'checkup_responses', count(*), count(contact_phone), count(contact_nss), count(contact_curp) FROM checkup_responses
      UNION ALL
      SELECT 'calculadora_submissions', count(*), count(contact_phone), NULL, NULL FROM calculadora_submissions
      """)
      |> Enum.map(fn [src, rows, phone, nss, curp] ->
        %{src: src, rows: rows, phone: phone, nss: nss, curp: curp}
      end)

    %{
      total_leads: total,
      with_nss: with_nss,
      with_curp: with_curp,
      with_afore: with_afore,
      with_nss_and_curp: nss_and_curp,
      with_all_three: all_three,
      over_60: over_60,
      age_known: age_known,
      weeks_over_850: weeks_over_850,
      weeks_known: weeks_known,
      inactive_1yr: inactive_1yr,
      activity_known: activity_known,
      emp_inactive: emp_inactive,
      emp_known: emp_known,
      afore_breakdown: afore,
      sources: sources,
      total_cases: total_cases,
      media_cases: media_cases
    }
  end

  @doc """
  Builds the full per-lead export as a UTF-8 CSV string (BOM-prefixed so
  Excel reads accents correctly). One row per lead (normalized phone),
  with **every column** from each source table — taking the latest record
  per source. Columns are prefixed by source (`customers.*`, `checkup.*`,
  `calculadora.*`, `pension_case.*`, `conversation.*`, `crm.*`).

  Column lists are read from `information_schema` on each call, so new
  bot-added columns appear in the export automatically.
  """
  def export_csv do
    {headers, rows} = build_export()

    body =
      [headers | rows]
      |> Enum.map_join("\r\n", fn row -> Enum.map_join(row, ",", &csv_field/1) end)

    "﻿" <> body <> "\r\n"
  end

  # ── internals ──────────────────────────────────────────────────────

  defp build_export do
    table_list = Enum.map_join(@export_sources, ",", fn s -> "'#{s.table}'" end)

    cols_by_table =
      query!("""
      SELECT table_name, column_name FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name IN (#{table_list})
      ORDER BY table_name, ordinal_position
      """)
      |> Enum.reduce(%{}, fn [t, c], acc -> Map.update(acc, t, [c], &(&1 ++ [c])) end)

    sources =
      Enum.map(@export_sources, fn s ->
        cols = Map.get(cols_by_table, s.table, [])
        Map.merge(s, %{cols: cols, order: Enum.find(@order_pref, &(&1 in cols))})
      end)

    union =
      Enum.map_join(sources, "\nUNION ALL\n", fn s ->
        "SELECT #{normp(s.phone)} AS p FROM #{s.table} t #{s.join} WHERE #{s.phone} IS NOT NULL"
      end)

    joins =
      Enum.map_join(sources, "\n", fn s ->
        collist = Enum.map_join(s.cols, ", ", fn c -> ~s|t."#{c}" AS "#{s.prefix}__#{c}"| end)
        order = if s.order, do: ~s|, t."#{s.order}" DESC NULLS LAST|, else: ""

        ~s|LEFT JOIN (SELECT DISTINCT ON (#{normp(s.phone)}) #{normp(s.phone)} AS p, #{collist} | <>
          ~s|FROM #{s.table} t #{s.join} WHERE #{s.phone} IS NOT NULL | <>
          ~s|ORDER BY #{normp(s.phone)}#{order}) #{s.prefix} ON #{s.prefix}.p = base.p|
      end)

    out_cols =
      Enum.flat_map(sources, fn s ->
        Enum.map(s.cols, fn c -> ~s|#{s.prefix}."#{s.prefix}__#{c}"| end)
      end)

    select_tail = if out_cols == [], do: "", else: ",\n" <> Enum.join(out_cols, ",\n")

    sql = """
    WITH base AS (
      SELECT DISTINCT p FROM (#{union}) u WHERE p <> '' AND length(p) = 10
    )
    SELECT base.p AS telefono#{select_tail}
    FROM base
    #{joins}
    ORDER BY base.p
    """

    headers =
      ["telefono"] ++
        Enum.flat_map(sources, fn s -> Enum.map(s.cols, &"#{s.prefix}.#{&1}") end)

    {headers, query!(sql)}
  end

  defp normp(expr), do: "right(regexp_replace(coalesce(#{expr},''),'[^0-9]','','g'),10)"

  # Shared `norm` CTE body (without the leading "WITH"): one normalized
  # row per source record, carrying every field both queries need.
  defp norm_cte do
    """
    norm AS (
      SELECT right(regexp_replace(coalesce(phone,''),'[^0-9]','','g'),10) AS p,
             nullif(nss,'') AS nss, nullif(curp,'') AS curp, NULL::text AS afore,
             CASE WHEN date_of_birth ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                  THEN to_date(date_of_birth,'YYYY-MM-DD') END AS birth,
             NULL::int AS age_int,
             weeks_contributed AS weeks,
             CASE WHEN last_imss_contribution_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                  THEN to_date(last_imss_contribution_date,'YYYY-MM-DD')
                  WHEN last_imss_contribution_date ~ '^[0-9]{4}-[0-9]{2}$'
                  THEN to_date(last_imss_contribution_date||'-01','YYYY-MM-DD') END AS activity,
             nullif(current_employment_status,'') AS emp,
             coalesce(nullif(full_name,''), nullif(display_name,'')) AS name,
             NULL::text AS email
      FROM customers WHERE phone IS NOT NULL
      UNION ALL
      SELECT right(regexp_replace(coalesce(contact_phone,''),'[^0-9]','','g'),10),
             nullif(contact_nss,''), nullif(contact_curp,''),
             CASE WHEN has_afore IS TRUE OR nullif(afore_name,'') IS NOT NULL
                  THEN coalesce(nullif(afore_name,''),'(unknown)') END,
             contact_birth_date, NULL, weeks_contributed,
             CASE WHEN last_year_cotized = 'working' THEN current_date
                  WHEN last_year_cotized ~ '^[0-9]{4}$' THEN make_date(last_year_cotized::int,12,31) END,
             NULL, nullif(contact_name,''), nullif(contact_email,'')
      FROM checkup_responses WHERE contact_phone IS NOT NULL
      UNION ALL
      SELECT right(regexp_replace(coalesce(contact_phone,''),'[^0-9]','','g'),10),
             NULL, NULL, NULL, birth_date, NULL, weeks_contributed, NULL,
             NULL, nullif(contact_name,''), nullif(contact_email,'')
      FROM calculadora_submissions WHERE contact_phone IS NOT NULL
      UNION ALL
      SELECT right(regexp_replace(coalesce(c.phone,''),'[^0-9]','','g'),10),
             NULL, NULL, NULL, NULL, pc.age, pc.weeks_contributed, NULL,
             nullif(pc.current_employment_status,''), NULL, NULL
      FROM pension_cases pc JOIN customers c ON pc.customer_id = c.id
      WHERE c.phone IS NOT NULL
    )
    """
  end

  defp query!(sql) do
    Ecto.Adapters.SQL.query!(Repo.active_repo(), sql).rows
  end

  defp csv_field(nil), do: ""
  defp csv_field(true), do: "sí"
  defp csv_field(false), do: "no"
  defp csv_field(%Decimal{} = d), do: Decimal.to_string(d)
  defp csv_field(%Date{} = d), do: Date.to_iso8601(d)
  defp csv_field(%DateTime{} = d), do: DateTime.to_iso8601(d)
  defp csv_field(%NaiveDateTime{} = d), do: NaiveDateTime.to_iso8601(d)
  defp csv_field(%Time{} = t), do: Time.to_iso8601(t)
  defp csv_field(v) when is_map(v) or is_list(v), do: csv_field(Jason.encode!(v))

  defp csv_field(v) when is_binary(v) do
    if String.contains?(v, [",", "\"", "\n", "\r"]) do
      "\"" <> String.replace(v, "\"", "\"\"") <> "\""
    else
      v
    end
  end

  defp csv_field(v), do: to_string(v)
end
