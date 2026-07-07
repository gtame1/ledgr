defmodule LedgrWeb.Domains.HelloDoctor.LifecycleController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.LifecycleMetrics

  def index(conn, params) do
    {start_date, end_date} = resolve_period(params)
    opts = opts_from(params)
    report = LifecycleMetrics.generate(start_date, end_date, opts)

    render(conn, :index,
      report: report,
      start_date: start_date,
      end_date: end_date,
      return_rate_param: params["return_rate"]
    )
  end

  def download(conn, params) do
    {start_date, end_date} = resolve_period(params)
    report = LifecycleMetrics.generate(start_date, end_date, opts_from(params))
    csv = to_csv(report)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="hello-doctor-unit-economics-#{start_date}-to-#{end_date}.csv")
    )
    |> send_resp(200, csv)
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp resolve_period(params) do
    {default_start, default_end} = LifecycleMetrics.default_period()

    {
      parse_date(params["start_date"]) || default_start,
      parse_date(params["end_date"]) || default_end
    }
  end

  defp opts_from(params) do
    case parse_rate(params["return_rate"]) do
      nil -> []
      r -> [return_rate: r]
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  # Accepts a fraction ("0.35") or a percent ("35"); returns a 0–1 float.
  defp parse_rate(nil), do: nil
  defp parse_rate(""), do: nil

  defp parse_rate(str) do
    case Float.parse(str) do
      {v, _} when v > 1.0 -> v / 100.0
      {v, _} when v >= 0.0 -> v
      _ -> nil
    end
  end

  # One CSV row per month: cohort conversion + spend + CPL/CAC.
  defp to_csv(report) do
    header = [
      "month",
      "engaged_base",
      "converted",
      "conv_pct",
      "spend_mxn",
      "leads",
      "cpl_mxn",
      "new_converted",
      "cac_mxn",
      "buildup_l1",
      "buildup_l2",
      "buildup_l3"
    ]

    econ_by = Map.new(report.unit_econ, &{{&1.year, &1.month}, &1})
    build_by = Map.new(report.buildup, &{{&1.year, &1.month}, &1})

    rows =
      Enum.map(report.cohorts, fn c ->
        e = Map.get(econ_by, {c.year, c.month}, %{})
        b = Map.get(build_by, {c.year, c.month}, %{})

        [
          "#{c.year}-#{pad(c.month)}",
          c.engaged,
          c.converted,
          c.conv_pct,
          Map.get(e, :spend, 0.0),
          Map.get(e, :leads, 0),
          Map.get(e, :cpl, 0.0),
          Map.get(e, :new_converted, 0),
          Map.get(e, :cac, 0.0),
          Map.get(b, :l1, 0),
          Map.get(b, :l2, 0),
          Map.get(b, :l3, 0)
        ]
      end)

    [header | rows]
    |> Enum.map_join("", fn row -> Enum.map_join(row, ",", &to_string/1) <> "\r\n" end)
  end

  defp pad(m) when m < 10, do: "0#{m}"
  defp pad(m), do: "#{m}"
end

defmodule LedgrWeb.Domains.HelloDoctor.LifecycleHTML do
  use LedgrWeb, :html

  embed_templates "lifecycle_html/*"

  @months {"", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

  def month_label(%{year: y, month: m}), do: "#{elem(@months, m)} #{y}"

  @doc ~s(Label for a week row, e.g. "Jul 6" — the week's Monday.)
  def week_label(%{week_start: %Date{} = d}), do: "#{elem(@months, d.month)} #{d.day}"
  def week_label(_), do: "—"

  def fmt_money(n) when is_number(n) do
    sign = if n < 0, do: "-", else: ""
    "#{sign}$#{:erlang.float_to_binary(abs(n) / 1, decimals: 2)}"
  end

  def fmt_money(_), do: "$0.00"

  def fmt_pct(n) when is_number(n), do: "#{:erlang.float_to_binary(n / 1, decimals: 1)}%"
  def fmt_pct(_), do: "0.0%"

  def fmt_ratio(n) when is_number(n), do: "#{:erlang.float_to_binary(n / 1, decimals: 2)}×"
  def fmt_ratio(_), do: "—"

  def fmt_num(n) when is_number(n), do: "#{:erlang.float_to_binary(n / 1, decimals: 1)}"
  def fmt_num(_), do: "—"

  @doc "Green when positive, red when negative — for net contribution figures."
  def sign_color(n) when is_number(n) and n < 0, do: "#dc2626"
  def sign_color(n) when is_number(n) and n > 0, do: "#065f46"
  def sign_color(_), do: "var(--text-main)"

  @doc "Width % for a stacked-bar segment relative to the max month total."
  def bar_pct(_v, 0), do: 0.0

  def bar_pct(v, max) when is_number(v) and is_number(max) and max > 0,
    do: Float.round(v / max * 100, 1)

  def bar_pct(_, _), do: 0.0
end
