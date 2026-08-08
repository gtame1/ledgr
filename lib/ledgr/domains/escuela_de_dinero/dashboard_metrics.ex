defmodule Ledgr.Domains.EscuelaDeDinero.DashboardMetrics do
  @moduledoc """
  Every aggregate behind the Panel.

  ## The metric that matters

  The bot's own stated success metric is the **share of people who complete the
  diagnóstico** — not inbound volume. `diagnostico_funnel/2` is therefore the
  centrepiece: it splits the run into `iniciado → playback → confirmado →
  entregado` so the drop-off is attributable to a step rather than a mood.

  ## Time handling

  Every timestamp the bot writes is `TIMESTAMPTZ`. Two rules follow:

    * Range bounds are built as real `DateTime`s in `America/Mexico_City`, not
      naive UTC — see `bounds/2`.
    * Daily buckets go through `AT TIME ZONE 'America/Mexico_City'` before the
      `::date` cast. Without it a message sent at 7pm Mexico City lands on
      tomorrow, and the last bar of every chart is wrong.

  ## What is deliberately not measured

    * `diagnosticos.status = "abandoned"` — the bot never writes it. A bucket
      that is structurally always zero reads as "nobody abandons".
    * `outbound_messages.status` — never advanced past `sent`. Send failures
      come from `policing_events.event_type = 'outbound_send_failed'` instead.
  """

  import Ecto.Query

  alias Ledgr.Domains.EscuelaDeDinero.Conversations.Conversation
  alias Ledgr.Domains.EscuelaDeDinero.Diagnosticos.Diagnostico
  alias Ledgr.Domains.EscuelaDeDinero.KuboReferrals.KuboReferral
  alias Ledgr.Domains.EscuelaDeDinero.Messages.Message
  alias Ledgr.Domains.EscuelaDeDinero.Movimientos.Movimiento
  alias Ledgr.Domains.EscuelaDeDinero.People.Person
  alias Ledgr.Domains.EscuelaDeDinero.PolicingEvents.PolicingEvent
  alias Ledgr.Repo

  @tz "America/Mexico_City"
  @etapas ~w(nuevo tc_pendiente diagnostico_en_curso diagnostico_listo acompanamiento)
  @areas ~w(colchon estructura_fiscal retiro seguros)
  @neon_cap_bytes 512 * 1024 * 1024

  @doc """
  Everything the Panel renders, in one call.

  `start_date`/`end_date` are `Date`s and bound only the windowed sections;
  state-of-the-world sections (etapas, áreas, movimientos) are all-time by
  design — they answer "where does the book stand", not "what happened lately".
  """
  def all(start_date, end_date) do
    %{
      kpis: kpis(start_date, end_date),
      diagnostico_funnel: diagnostico_funnel(start_date, end_date),
      etapa_funnel: etapa_funnel(),
      dias_distribution: dias_distribution(),
      areas: areas_breakdown(),
      movimientos: movimientos_breakdown(),
      daily_series: daily_series(start_date, end_date),
      salud: salud(start_date, end_date),
      atorados: atorados(5),
      db_size: db_size()
    }
  end

  # ── KPI row ────────────────────────────────────────────────────────

  def kpis(start_date, end_date) do
    funnel = diagnostico_funnel(start_date, end_date)

    %{
      personas_nuevas: count_in_window(Person, :created_at, start_date, end_date),
      iniciados: funnel.iniciados,
      entregados: funnel.entregados,
      tasa_completado: rate(funnel.entregados, funnel.iniciados)
    }
  end

  # ── Embudo del diagnóstico ─────────────────────────────────────────

  @doc """
  The four stamps of a diagnóstico run, counted in one pass.

  Stamps are cumulative in practice but not enforced to be: `confirmed_at` is
  cleared when the person corrects a material answer after the playback, so a
  row can hold `playback_sent_at` without `confirmed_at` and later regain it.
  Each count is therefore independent rather than derived from the previous.
  """
  def diagnostico_funnel(start_date, end_date) do
    {from_dt, to_dt} = bounds(start_date, end_date)

    Repo.one(
      from d in Diagnostico,
        where: d.started_at >= ^from_dt and d.started_at <= ^to_dt,
        select: %{
          iniciados: count(d.id),
          playback: filter(count(d.id), not is_nil(d.playback_sent_at)),
          confirmados: filter(count(d.id), not is_nil(d.confirmed_at)),
          entregados: filter(count(d.id), d.status == "complete"),
          en_curso: filter(count(d.id), d.status == "in_progress")
        }
    ) || %{iniciados: 0, playback: 0, confirmados: 0, entregados: 0, en_curso: 0}
  end

  @doc """
  The funnel as ordered rows, each with its share of the top of funnel and its
  step-over-step conversion. Ready to render as bars.
  """
  def diagnostico_funnel_rows(funnel) do
    steps = [
      {"Iniciado", funnel.iniciados},
      {"Playback enviado", funnel.playback},
      {"Confirmado", funnel.confirmados},
      {"Entregado", funnel.entregados}
    ]

    top = funnel.iniciados

    steps
    |> Enum.with_index()
    |> Enum.map(fn {{label, count}, i} ->
      prev = if i == 0, do: nil, else: steps |> Enum.at(i - 1) |> elem(1)

      %{
        label: label,
        count: count,
        share: rate(count, top),
        step_rate: if(prev, do: rate(count, prev))
      }
    end)
  end

  # ── Embudo por etapa ───────────────────────────────────────────────

  @doc """
  People at or beyond each etapa.

  `etapa` is monotonic and terminal — it only ever moves forward — so a
  cumulative "reached this stage" read is legitimate, and the drop between
  `nuevo` and `tc_pendiente` is a real measure of the consent gate.
  """
  def etapa_funnel do
    counts =
      Repo.all(from p in Person, group_by: p.etapa, select: {p.etapa, count(p.id)})
      |> Map.new()

    # Only etapas we know about contribute to the total. The bot owns
    # `ETAPA_ORDER` and can grow it; if an unmapped value counted toward the
    # total it would never be consumed by the walk below, so every bar would
    # inflate by that many people and the funnel would quietly overstate every
    # stage forever. Surface the unknowns instead — same reasoning as rendering
    # a missing `areas` key as "sin dato" rather than dropping it.
    known = Map.take(counts, @etapas)
    total = known |> Map.values() |> Enum.sum()

    desconocidas =
      counts
      |> Map.drop(@etapas)
      |> Enum.sort_by(fn {_etapa, n} -> -n end)

    {rows, _} =
      Enum.map_reduce(@etapas, 0, fn etapa, consumed ->
        at_or_beyond = total - consumed
        here = Map.get(known, etapa, 0)

        row = %{
          etapa: etapa,
          reached: at_or_beyond,
          here: here,
          share: rate(at_or_beyond, total)
        }

        {row, consumed + here}
      end)

    %{total: total, rows: rows, desconocidas: desconocidas}
  end

  # ── Días sin facturar ──────────────────────────────────────────────

  @doc """
  Distribution of the headline number across each person's *latest* completed
  diagnóstico, joined through the denormalized `latest_diagnostico_id` pointer.

  Bands are the bot's own colchón thresholds (30 / 90) plus a "less than a
  week" band. Reports the **median**, not the mean — with a handful of people
  one outlier moves a mean by tens of days.
  """
  def dias_distribution do
    stats =
      Repo.one(
        from p in Person,
          join: d in Diagnostico,
          on: d.id == p.latest_diagnostico_id,
          where: d.status == "complete" and not is_nil(d.dias_sin_facturar),
          select: %{
            total: count(d.id),
            b_critico: filter(count(d.id), d.dias_sin_facturar < 7),
            b_corto: filter(count(d.id), d.dias_sin_facturar >= 7 and d.dias_sin_facturar < 30),
            b_medio: filter(count(d.id), d.dias_sin_facturar >= 30 and d.dias_sin_facturar < 90),
            b_largo: filter(count(d.id), d.dias_sin_facturar >= 90),
            mediana:
              fragment("percentile_cont(0.5) WITHIN GROUP (ORDER BY ?)", d.dias_sin_facturar)
          }
      ) || %{total: 0, b_critico: 0, b_corto: 0, b_medio: 0, b_largo: 0, mediana: nil}

    bands = [
      %{band: :critico, count: stats.b_critico},
      %{band: :corto, count: stats.b_corto},
      %{band: :medio, count: stats.b_medio},
      %{band: :largo, count: stats.b_largo}
    ]

    %{
      total: stats.total,
      mediana: round_or_nil(stats.mediana),
      bands: Enum.map(bands, &Map.put(&1, :share, rate(&1.count, stats.total)))
    }
  end

  # ── Áreas / sellos ─────────────────────────────────────────────────

  @doc """
  For each área, how many people's latest diagnóstico has it `al_descubierto` /
  `en_proceso` / `instalado`.

  A missing key comes back as `"sin_dato"` rather than being dropped — if the
  bot changes the shape of `areas`, that should show up on the Panel instead of
  silently shrinking every bar.
  """
  def areas_breakdown do
    Enum.map(@areas, fn area ->
      # `selected_as` is load-bearing: writing the same fragment twice makes
      # Ecto emit two parameter placeholders ($1 in SELECT, $2 in GROUP BY),
      # and Postgres compares grouping expressions textually — it sees two
      # different expressions and rejects the query.
      counts =
        Repo.all(
          from p in Person,
            join: d in Diagnostico,
            on: d.id == p.latest_diagnostico_id,
            where: d.status == "complete",
            group_by: selected_as(:estado),
            select:
              {selected_as(fragment("(? -> ? ->> 'estado')", d.areas, ^area), :estado),
               count(d.id)}
        )
        |> Enum.map(fn {estado, n} -> {estado || "sin_dato", n} end)
        |> Map.new()

      total = counts |> Map.values() |> Enum.sum()

      segments =
        ~w(al_descubierto en_proceso instalado sin_dato)
        |> Enum.map(fn estado ->
          n = Map.get(counts, estado, 0)
          %{estado: estado, count: n, share: rate(n, total)}
        end)
        |> Enum.reject(&(&1.count == 0))

      %{area: area, total: total, segments: segments}
    end)
  end

  # ── Movimientos ────────────────────────────────────────────────────

  @doc """
  The acompañamiento queue in aggregate.

  `tasa_instalacion` counts `hecho` against every movimiento ever authored,
  `descartado` included — a discarded move is still a move that didn't get
  installed, and excluding it would flatter the number.
  """
  def movimientos_breakdown do
    by_estado =
      Repo.all(from m in Movimiento, group_by: m.estado, select: {m.estado, count(m.id)})
      |> Map.new()

    total = by_estado |> Map.values() |> Enum.sum()
    hechos = Map.get(by_estado, "hecho", 0)

    vencidos =
      Repo.one(
        from m in Movimiento,
          where: m.estado == "pendiente" and m.due_at < ^DateTime.utc_now(),
          select: count(m.id)
      ) || 0

    # Pendientes that have exhausted their three nudges. The sweep will never
    # touch them again, so nothing will move without a human.
    agotados =
      Repo.one(
        from m in Movimiento,
          where: m.estado == "pendiente" and m.checkin_count >= 3,
          select: count(m.id)
      ) || 0

    por_area =
      Repo.all(
        from m in Movimiento,
          group_by: [m.area, m.estado],
          select: {m.area, m.estado, count(m.id)}
      )
      |> Enum.group_by(fn {area, _, _} -> area end, fn {_, estado, n} -> {estado, n} end)
      |> Map.new(fn {area, pairs} -> {area, Map.new(pairs)} end)

    %{
      total: total,
      by_estado: by_estado,
      por_area: por_area,
      vencidos: vencidos,
      agotados: agotados,
      tasa_instalacion: rate(hechos, total)
    }
  end

  # ── Serie diaria ───────────────────────────────────────────────────

  @doc """
  One row per calendar day in the window, so gaps render as zero rather than
  collapsing the x-axis.
  """
  def daily_series(start_date, end_date) do
    {from_dt, to_dt} = bounds(start_date, end_date)

    nuevas = daily_counts(Person, :created_at, from_dt, to_dt)
    iniciados = daily_counts(Diagnostico, :started_at, from_dt, to_dt)
    entregados = daily_counts(Diagnostico, :completed_at, from_dt, to_dt)
    mensajes = daily_inbound_counts(from_dt, to_dt)

    start_date
    |> Date.range(end_date)
    |> Enum.map(fn day ->
      %{
        date: day,
        personas: Map.get(nuevas, day, 0),
        iniciados: Map.get(iniciados, day, 0),
        entregados: Map.get(entregados, day, 0),
        mensajes: Map.get(mensajes, day, 0)
      }
    end)
  end

  # `selected_as` rather than repeating the fragment: written twice, Ecto emits
  # a separate placeholder for the pinned timezone in each ($1 in SELECT, $4 in
  # GROUP BY), and Postgres compares grouping expressions textually — it sees
  # two different expressions and rejects the query.
  defp daily_counts(schema, field, from_dt, to_dt) do
    Repo.all(
      from q in schema,
        where:
          field(q, ^field) >= ^from_dt and field(q, ^field) <= ^to_dt and
            not is_nil(field(q, ^field)),
        group_by: selected_as(:day),
        select:
          {selected_as(fragment("(? AT TIME ZONE ?)::date", field(q, ^field), ^@tz), :day),
           count(field(q, :id))}
    )
    |> Map.new()
  end

  defp daily_inbound_counts(from_dt, to_dt) do
    Repo.all(
      from m in Message,
        where: m.role == "user" and m.created_at >= ^from_dt and m.created_at <= ^to_dt,
        group_by: selected_as(:day),
        select:
          {selected_as(fragment("(? AT TIME ZONE ?)::date", m.created_at, ^@tz), :day),
           count(m.id)}
    )
    |> Map.new()
  end

  # ── Franja de salud ────────────────────────────────────────────────

  @doc """
  The strip of things that should be watched but rarely change.

  Guardrail counts are a rolling 7 days regardless of the page's date window —
  "were we compliant this week" is not a question you want silently rescoped by
  a filter someone left set to last March.
  """
  def salud(_start_date, _end_date) do
    since = DateTime.add(DateTime.utc_now(), -7, :day)
    now = DateTime.utc_now()

    %{
      criticos: count_policing(since, severity: "CRITICAL"),
      advertencias: count_policing(since, severity: "WARNING"),
      # NOT outbound_messages.status — that column is never advanced.
      fallos_envio: count_policing(since, event_type: "outbound_send_failed"),
      sesiones_activas:
        Repo.one(from c in Conversation, where: c.status == "active", select: count(c.id)) || 0,
      ventana_abierta:
        Repo.one(
          from c in Conversation,
            where: c.status == "active" and c.freeform_until > ^now,
            select: count(c.id)
        ) || 0,
      bajas:
        Repo.one(from p in Person, where: not is_nil(p.opted_out_at), select: count(p.id)) || 0,
      # An affiliate link that went out without the commercial-relationship
      # declaration. Must always be zero.
      kubo_sin_declaracion: kubo_sin_declaracion()
    }
  end

  defp count_policing(since, severity: severity) do
    Repo.one(
      from e in PolicingEvent,
        where: e.severity == ^severity and e.ts >= ^since,
        select: count(e.id)
    ) || 0
  end

  defp count_policing(since, event_type: event_type) do
    Repo.one(
      from e in PolicingEvent,
        where: e.event_type == ^event_type and e.ts >= ^since,
        select: count(e.id)
    ) || 0
  end

  @doc "Referrals whose link shipped without the disclosure message. Always 0."
  def kubo_sin_declaracion do
    Repo.one(
      from k in KuboReferral,
        where: not is_nil(k.link_url) and is_nil(k.disclosure_message_id),
        select: count(k.id)
    ) || 0
  end

  # ── Atorados ───────────────────────────────────────────────────────

  @doc """
  People who started the diagnóstico and went quiet.

  With completion rate as the north star this is the only list on the Panel
  that tells an operator what to actually do. Ordered oldest-silence first.
  """
  def atorados(limit) do
    cutoff = DateTime.add(DateTime.utc_now(), -7, :day)

    Repo.all(
      from p in Person,
        left_join: c in Conversation,
        on: c.person_id == p.id,
        where: p.etapa == "diagnostico_en_curso" and is_nil(p.opted_out_at),
        group_by: p.id,
        having: max(c.last_inbound_at) < ^cutoff or is_nil(max(c.last_inbound_at)),
        order_by: [asc_nulls_first: max(c.last_inbound_at)],
        limit: ^limit,
        select: %{
          id: p.id,
          phone: p.phone,
          display_name: p.display_name,
          created_at: p.created_at,
          last_inbound_at: max(c.last_inbound_at)
        }
    )
  end

  # ── DB size ────────────────────────────────────────────────────────

  @doc "Neon storage against the free-tier cap."
  def db_size do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo.active_repo(),
        "SELECT pg_database_size(current_database())"
      )

    bytes = rows |> List.first() |> List.first() || 0

    %{
      bytes: bytes,
      mb: Float.round(bytes / (1024 * 1024), 1),
      cap_mb: 512,
      percent: Float.round(bytes / @neon_cap_bytes * 100, 1)
    }
  end

  # ── Private ────────────────────────────────────────────────────────

  # Real DateTime bounds in Mexico City. The bot writes TIMESTAMPTZ, so naive
  # UTC bounds would shift every window by six hours.
  defp bounds(%Date{} = start_date, %Date{} = end_date) do
    {DateTime.new!(start_date, ~T[00:00:00], @tz),
     DateTime.new!(end_date, ~T[23:59:59.999999], @tz)}
  end

  defp count_in_window(schema, field, start_date, end_date) do
    {from_dt, to_dt} = bounds(start_date, end_date)

    Repo.one(
      from q in schema,
        where: field(q, ^field) >= ^from_dt and field(q, ^field) <= ^to_dt,
        select: count(field(q, :id))
    ) || 0
  end

  # Every rate on the Panel goes through here so an empty database renders
  # "0%" rather than raising on a division by zero.
  defp rate(_numerator, 0), do: 0.0
  defp rate(_numerator, nil), do: 0.0
  defp rate(nil, _denominator), do: 0.0
  defp rate(numerator, denominator), do: Float.round(numerator / denominator * 100, 1)

  defp round_or_nil(nil), do: nil
  defp round_or_nil(%Decimal{} = d), do: d |> Decimal.round(0) |> Decimal.to_integer()
  defp round_or_nil(n) when is_float(n), do: round(n)
  defp round_or_nil(n) when is_integer(n), do: n
end
