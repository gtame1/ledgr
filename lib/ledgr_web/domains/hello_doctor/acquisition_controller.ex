defmodule LedgrWeb.Domains.HelloDoctor.AcquisitionController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.AcquisitionMetrics

  def index(conn, params) do
    {start_date, end_date} = resolve_period(params)

    # Full-range report drives the top KPI cards + daily trend chart.
    report = AcquisitionMetrics.generate(start_date, end_date)

    # One funnel table per tracking cut (newest first), each windowed to
    # its era within the picker range. See AcquisitionMetrics.cut_tables/2.
    cut_tables = AcquisitionMetrics.cut_tables(start_date, end_date)

    render(conn, :index,
      report: report,
      cut_tables: cut_tables,
      start_date: start_date,
      end_date: end_date
    )
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp resolve_period(params) do
    {default_start, default_end} = AcquisitionMetrics.last_30_days()

    {
      parse_date(params["start_date"]) || default_start,
      parse_date(params["end_date"]) || default_end
    }
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.AcquisitionHTML do
  use LedgrWeb, :html
  embed_templates "acquisition_html/*"

  @doc """
  Distinct color per campaign for the chart legend + stacked bars.
  Same-keyed across the table and the SVG so a glance ties them
  together. Built from a fixed palette so colors don't shift on add.
  """
  @palette %{
    "gin_01" => "#0ea5e9",
    "gin_02" => "#a855f7",
    "ped_01" => "#f59e0b",
    "gen_01_thinking" => "#10b981",
    "gen_01_smile" => "#14b8a6",
    "awr_01" => "#ef4444",
    "lpc_01" => "#6366f1",
    "lph_01" => "#ec4899",
    # Meta cohort launched 2026-06-17
    "gine_manchado" => "#be185d",
    "gast_estomago" => "#0891b2",
    "ped_bebe_enfermo" => "#ea580c"
  }

  def campaign_color(id), do: Map.get(@palette, id, "#94a3b8")

  @doc """
  Color for each early funnel-stage cell. These are all mid-funnel
  stepping-stones now (greeting → payment_link_sent), so they stay in
  the default text color; the eye-catching colors live on the outcome
  columns instead (see `Ledgr.Domains.HelloDoctor.AcquisitionMetrics.outcome_stages/0`).
  """
  def stage_cell_color(_), do: "var(--text-main)"

  @doc "MXN money formatter."
  def fmt_money(n) when is_number(n) do
    "$" <> :erlang.float_to_binary(n / 1, decimals: 2) <> " MXN"
  end

  def fmt_money(_), do: "—"

  @doc "Percent with one decimal."
  def fmt_pct(n) when is_number(n), do: :erlang.float_to_binary(n / 1, decimals: 1) <> "%"
  def fmt_pct(_), do: "—"

  @doc """
  Returns `count / column_total * 100` as a float, or `0.0` when the
  column total is missing or zero. Used by the acquisition table's
  per-cell hover tooltip to show what share of each stage's total came
  from a given campaign — e.g. "GIN-02 = 60% of doctor_search".
  """
  def column_share(_count, nil), do: 0.0
  def column_share(_count, 0), do: 0.0
  def column_share(nil, _total), do: 0.0

  def column_share(count, total) when is_number(count) and is_number(total) and total > 0,
    do: Float.round(count / total * 100, 1)

  def column_share(_, _), do: 0.0

  @doc """
  Precomputes the stacked-bar segments for a single day. Returns a list
  of `%{campaign_id, color, height, y_top}` ordered the way they should
  stack (palette/PDF order, bottom-up). `chart_h` is the total chart
  height; `max_total` is the max across all days (for vertical scaling).
  """
  def day_segments(row, per_campaign, max_total, chart_h) do
    # Bottom of the chart is `chart_h`; we accumulate upward from there.
    {segs, _} =
      Enum.reduce(per_campaign, {[], chart_h}, fn entry, {acc, y_bottom} ->
        seg_count = Map.get(row.by_campaign, entry.campaign.id, 0)

        height =
          if max_total <= 0 or seg_count == 0,
            do: 0,
            else: round(seg_count / max_total * chart_h)

        if height == 0 do
          {acc, y_bottom}
        else
          y_top = y_bottom - height

          seg = %{
            campaign_id: entry.campaign.id,
            color: campaign_color(entry.campaign.id),
            height: height,
            y_top: y_top,
            count: seg_count,
            ad_set: entry.campaign.ad_set,
            emoji: entry.campaign.emoji
          }

          {[seg | acc], y_top}
        end
      end)

    Enum.reverse(segs)
  end

  @doc """
  The per-campaign funnel table. Shared by the all-campaigns view and
  each launch-cohort sub-table so they render identically.

    * `entries` — `report.per_campaign` (or a filtered subset).
    * `totals`  — the matching totals map (`report.totals`, or
      `AcquisitionMetrics.subtotals/1` for a subset) — drives the footer
      and the per-cell column-share tooltips.
    * `stages`   — `AcquisitionMetrics.canonical_stages/0` (cumulative
      early-funnel columns).
    * `outcomes` — `AcquisitionMetrics.outcome_stages/0` (independent
      source-of-truth outcome columns: paid / consult / done / etc.).
  """
  attr :entries, :list, required: true
  attr :totals, :map, required: true
  attr :stages, :list, required: true
  attr :outcomes, :list, required: true

  def funnel_table(assigns) do
    ~H"""
    <div class="hd-card" style="padding: 0; overflow-x: auto; margin-bottom: 2rem;">
      <table class="w-full text-sm" style="min-width: 100%;">
        <thead>
          <tr style="border-bottom: 1px solid var(--border-subtle); background: var(--bg-secondary);">
            <th
              class="text-left p-3 pl-4 text-xs font-semibold uppercase"
              style="color: var(--text-muted); white-space: nowrap;"
            >
              Campaign
            </th>
            <th
              class="text-right p-3 text-xs font-semibold uppercase"
              style="color: var(--text-muted); white-space: nowrap;"
            >
              Leads
            </th>
            <th
              class="text-right p-3 text-xs font-semibold uppercase"
              style="color: var(--text-muted); white-space: nowrap;"
            >
              Patients
            </th>
            <th
              class="text-right p-3 text-xs font-semibold uppercase"
              style="color: var(--text-muted); white-space: nowrap;"
              title="Ad clicks paused at the bot's '¿te refirió un doctor?' prompt — awaiting a yes/no button tap. Transient."
            >
              Pending routing
            </th>
            <th
              :for={s <- @stages}
              class="text-right p-3 text-xs font-semibold uppercase"
              style="color: var(--text-muted); white-space: nowrap;"
              title={"Stage #{s.idx}: #{s.label} (cumulative — includes everyone past this stage)"}
            >
              {s.idx}. {s.short}
            </th>
            <th
              :for={o <- @outcomes}
              class="text-right p-3 text-xs font-semibold uppercase"
              style="color: var(--text-muted); white-space: nowrap; border-left: 1px solid var(--border-subtle);"
              title={"#{o.label} — measured from consultations / stripe_payments, not funnel_stage (independent, not cumulative)"}
            >
              {o.short}
            </th>
            <th
              class="text-right p-3 pr-4 text-xs font-semibold uppercase"
              style="color: var(--text-muted); white-space: nowrap;"
            >
              Revenue
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- @entries} style="border-bottom: 1px solid var(--border-subtle);">
            <td class="p-3 pl-4 font-medium" style="color: var(--text-main); white-space: nowrap;">
              <span style={"display:inline-block;width:8px;height:8px;background:#{campaign_color(entry.campaign.id)};border-radius:50%;margin-right:0.4rem;vertical-align:middle;"}>
              </span>
              {entry.campaign.emoji} {entry.campaign.ad_set}
              <div class="text-xs mt-0.5" style="color: var(--text-muted);">
                {entry.campaign.campaign_set} · {entry.campaign.pain}
              </div>
            </td>
            <td class="p-3 text-right font-semibold">{entry.leads}</td>
            <td class="p-3 text-right">{entry.unique_patients}</td>
            <% pending_share = column_share(entry.pending_routing, @totals.pending_routing) %>
            <td
              class="hd-tooltip-cell p-3 text-right"
              style="color: var(--text-muted);"
              data-tip={"#{fmt_pct(pending_share)} of pending routing"}
            >
              {entry.pending_routing}
            </td>
            <%= for s <- @stages do %>
              <% count = Map.get(entry, s.key) %>
              <% col_total = Map.get(@totals, s.key) %>
              <% share = column_share(count, col_total) %>
              <td
                class="hd-tooltip-cell p-3 text-right"
                style={"color: #{stage_cell_color(s.idx)};"}
                data-tip={"#{fmt_pct(share)} of #{s.label}"}
              >
                {count}
              </td>
            <% end %>
            <%= for o <- @outcomes do %>
              <% count = Map.get(entry, o.key) %>
              <% col_total = Map.get(@totals, o.key) %>
              <% share = column_share(count, col_total) %>
              <td
                class="hd-tooltip-cell p-3 text-right font-semibold"
                style={"color: #{o.color}; border-left: 1px solid var(--border-subtle);"}
                data-tip={"#{fmt_pct(share)} of #{o.label}"}
              >
                {count}
              </td>
            <% end %>
            <td class="p-3 pr-4 text-right font-semibold">
              {fmt_money(entry.revenue_mxn)}
            </td>
          </tr>
        </tbody>
        <tfoot>
          <tr style="background: var(--bg-secondary); border-top: 2px solid var(--border-strong);">
            <td class="p-3 pl-4 font-bold" style="white-space: nowrap;">Totals</td>
            <td class="p-3 text-right font-bold">{@totals.leads}</td>
            <td class="p-3 text-right font-bold">{@totals.unique_patients}</td>
            <td
              class="hd-tooltip-cell p-3 text-right font-bold"
              style="color: var(--text-muted);"
              data-tip={"#{fmt_pct(@totals.pending_routing_pct)} of all leads"}
            >
              {@totals.pending_routing}
            </td>
            <%= for s <- @stages do %>
              <% pct_of_leads = Map.get(@totals, :"pct_#{s.idx}") %>
              <td
                class="hd-tooltip-cell p-3 text-right font-bold"
                style={"color: #{stage_cell_color(s.idx)};"}
                data-tip={"#{fmt_pct(pct_of_leads)} of all leads reached #{s.label}"}
              >
                {Map.get(@totals, s.key)}
              </td>
            <% end %>
            <%= for o <- @outcomes do %>
              <% pct_of_leads = Map.get(@totals, :"pct_#{o.key}") %>
              <td
                class="hd-tooltip-cell p-3 text-right font-bold"
                style={"color: #{o.color}; border-left: 1px solid var(--border-subtle);"}
                data-tip={"#{fmt_pct(pct_of_leads)} of all leads · #{o.label}"}
              >
                {Map.get(@totals, o.key)}
              </td>
            <% end %>
            <td class="p-3 pr-4 text-right font-bold">{fmt_money(@totals.revenue_mxn)}</td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  @doc """
  Heading for a tracking-era table (from `AcquisitionMetrics.cut_tables/2`):
  "From Jun 24, 2026" (current/open-ended), "Before Jun 17, 2026" (pre-first
  cut), or "Jun 17 – Jun 23, 2026" (a closed window between two cuts).
  """
  def cut_title(%{upper: nil, lower: l}), do: "From " <> Calendar.strftime(l, "%b %-d, %Y")
  def cut_title(%{lower: nil, upper: u}), do: "Before " <> Calendar.strftime(u, "%b %-d, %Y")

  def cut_title(%{lower: l, upper: u}) do
    Calendar.strftime(l, "%b %-d") <> " – " <> Calendar.strftime(Date.add(u, -1), "%b %-d, %Y")
  end

  @doc """
  Renders one tracking-era funnel table, or a muted note when the picker
  range doesn't overlap the era. Shared by the expanded (current) cut and
  the collapsed (`<details>`) older cuts so they render identically.
  """
  attr :cut, :map, required: true
  attr :stages, :list, required: true
  attr :outcomes, :list, required: true

  def cut_table(assigns) do
    ~H"""
    <%= if @cut.empty? do %>
      <p class="text-sm" style="color: var(--text-muted); padding: 0.5rem 0;">
        No days in this window for the selected range — widen the From/To dates above.
      </p>
    <% else %>
      <% {win_start, win_end} = @cut.window %>
      <p class="text-xs mb-2" style="color: var(--text-muted);">
        Showing {Calendar.strftime(win_start, "%b %-d")} – {Calendar.strftime(win_end, "%b %-d, %Y")} · {@cut.totals.leads} leads
      </p>
      <.funnel_table entries={@cut.entries} totals={@cut.totals} stages={@stages} outcomes={@outcomes} />
    <% end %>
    """
  end
end
