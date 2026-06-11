defmodule LedgrWeb.Domains.HelloDoctor.AcquisitionController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.AcquisitionMetrics

  def index(conn, params) do
    {start_date, end_date} = resolve_period(params)
    report = AcquisitionMetrics.generate(start_date, end_date)

    render(conn, :index,
      report: report,
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
    "lph_01" => "#ec4899"
  }

  def campaign_color(id), do: Map.get(@palette, id, "#94a3b8")

  @doc """
  Color hint for each canonical funnel-stage cell. Money-bearing
  stages (payment_confirmed, consultation_complete) get green/accent
  emphasis; the failure terminal gets a muted red; everything
  mid-funnel stays in the default text color so the eye isn't pulled
  to columns that are just stepping-stones.
  """
  def stage_cell_color(7), do: "#16a34a"
  def stage_cell_color(11), do: "var(--accent)"
  def stage_cell_color(12), do: "#dc2626"
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
end
