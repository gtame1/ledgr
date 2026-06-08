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
    "awr_01" => "#ef4444"
  }

  def campaign_color(id), do: Map.get(@palette, id, "#94a3b8")

  @doc "MXN money formatter."
  def fmt_money(n) when is_number(n) do
    "$" <> :erlang.float_to_binary(n / 1, decimals: 2) <> " MXN"
  end

  def fmt_money(_), do: "—"

  @doc "Percent with one decimal."
  def fmt_pct(n) when is_number(n), do: :erlang.float_to_binary(n / 1, decimals: 1) <> "%"
  def fmt_pct(_), do: "—"

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
