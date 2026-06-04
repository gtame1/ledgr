defmodule Ledgr.Domains.AumentaMiPension.TraspasoCoverage do
  @moduledoc """
  Data-quality metrics for the AFORE *traspaso* requirements.

  Measures, across the unified "lead" universe (a distinct person keyed
  by normalized 10-digit phone, unioned from `customers`,
  `checkup_responses` and `calculadora_submissions`), how many leads
  carry each field needed to start an AFORE transfer:

    1. Current AFORE                  → `checkup_responses.afore_name` / `has_afore`
    2. Last AFORE change > 1 year ago → NOT captured anywhere (no field)
    3. NSS + CURP (for validation)    → `customers` + `checkup_responses`
    4. Not on the exclusion list      → NOT captured anywhere (no field)
    5. Comprobante de domicilio + ID  → no structured field; loose proxy is
                                         `pension_cases.media_analyses`

  Everything is computed live from the bot-shared Postgres on each call.
  Phone normalization mirrors `Phones.normalize/1` enough for counting:
  strip non-digits, take the last 10. Cheap at lead counts in the
  low thousands; revisit with an expression index if it gets slow.
  """

  alias Ledgr.Repo

  @doc """
  Returns the full coverage snapshot as a map. See module doc for the
  field → requirement mapping.
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
        activity_known
      ]
    ] =
      query!("""
      WITH norm AS (
        SELECT right(regexp_replace(coalesce(phone,''),'[^0-9]','','g'),10) AS p,
               nullif(nss,'') AS nss, nullif(curp,'') AS curp, NULL::text AS afore,
               CASE WHEN date_of_birth ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                    THEN to_date(date_of_birth,'YYYY-MM-DD') END AS birth,
               NULL::int AS age_int,
               weeks_contributed AS weeks,
               CASE WHEN last_imss_contribution_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                    THEN to_date(last_imss_contribution_date,'YYYY-MM-DD')
                    WHEN last_imss_contribution_date ~ '^[0-9]{4}-[0-9]{2}$'
                    THEN to_date(last_imss_contribution_date||'-01','YYYY-MM-DD') END AS activity
        FROM customers WHERE phone IS NOT NULL
        UNION ALL
        SELECT right(regexp_replace(coalesce(contact_phone,''),'[^0-9]','','g'),10),
               nullif(contact_nss,''), nullif(contact_curp,''),
               CASE WHEN has_afore IS TRUE OR nullif(afore_name,'') IS NOT NULL
                    THEN coalesce(nullif(afore_name,''),'(unknown)') END,
               contact_birth_date, NULL, weeks_contributed,
               CASE WHEN last_year_cotized = 'working' THEN current_date
                    WHEN last_year_cotized ~ '^[0-9]{4}$' THEN make_date(last_year_cotized::int,12,31) END
        FROM checkup_responses WHERE contact_phone IS NOT NULL
        UNION ALL
        SELECT right(regexp_replace(coalesce(contact_phone,''),'[^0-9]','','g'),10),
               NULL, NULL, NULL, birth_date, NULL, weeks_contributed, NULL
        FROM calculadora_submissions WHERE contact_phone IS NOT NULL
        UNION ALL
        SELECT right(regexp_replace(coalesce(c.phone,''),'[^0-9]','','g'),10),
               NULL, NULL, NULL, NULL, pc.age, pc.weeks_contributed, NULL
        FROM pension_cases pc JOIN customers c ON pc.customer_id = c.id
        WHERE c.phone IS NOT NULL
      ),
      leads AS (
        SELECT p,
               bool_or(nss IS NOT NULL)  AS has_nss,
               bool_or(curp IS NOT NULL) AS has_curp,
               bool_or(afore IS NOT NULL) AS has_afore,
               greatest(max(age_int), max(extract(year from age(current_date, birth))::int)) AS age,
               max(weeks) AS weeks,
               max(activity) AS last_activity
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
             count(*) FILTER (WHERE last_activity IS NOT NULL)
      FROM leads
      """)

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
      afore_breakdown: afore,
      sources: sources,
      total_cases: total_cases,
      media_cases: media_cases
    }
  end

  defp query!(sql) do
    Ecto.Adapters.SQL.query!(Repo.active_repo(), sql).rows
  end
end
