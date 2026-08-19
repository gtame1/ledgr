defmodule LedgrWeb.Domains.HelloDoctor.DashboardController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor
  alias Ledgr.Domains.HelloDoctor.BillingSync
  alias Ledgr.Domains.HelloDoctor.DashboardMetrics
  alias Ledgr.Core.Settings

  @doc """
  Hello Doctor's operational dashboard.

  Moved off the shared `ReportController` so this domain stops routing the
  accounting surface at all — the same shape Escuela de Dinero already uses.
  `resolve_period/1` is deliberately duplicated here rather than shared: the
  original was private to `ReportController`, and the three domains' period
  semantics are diverging anyway.
  """
  def index(conn, params) do
    # HD defaults to the last 30 days rather than the calendar month.
    params =
      if not Map.has_key?(params, "period") and not Map.has_key?(params, "start_date") and
           not Map.has_key?(params, "all_dates") do
        Map.put(params, "period", "last_30_days")
      else
        params
      end

    {start_date, end_date} = resolve_period(params)
    {earliest_date, latest_date} = HelloDoctor.data_date_range()

    render(conn, :index,
      metrics: HelloDoctor.dashboard_metrics(start_date, end_date),
      comparison: comparison(params, start_date, end_date),
      start_date: start_date,
      end_date: end_date,
      earliest_date: earliest_date,
      latest_date: latest_date,
      current_period: params["period"],
      usd_mxn_rate: Settings.get_usd_mxn_rate()
    )
  end

  # Prior equal-length window immediately preceding the current one, for the
  # period-over-period delta chips. Skipped for "all time", which has no
  # meaningful prior period.
  defp comparison(%{"period" => "all_time"}, _start_date, _end_date), do: nil
  defp comparison(%{"all_dates" => "true"}, _start_date, _end_date), do: nil

  defp comparison(_params, start_date, end_date) do
    len = Date.diff(end_date, start_date) + 1
    prior_end = Date.add(start_date, -1)
    prior_start = Date.add(prior_end, -(len - 1))

    prior_start
    |> DashboardMetrics.period_summary(prior_end)
    |> Map.merge(%{start_date: prior_start, end_date: prior_end})
  end

  defp resolve_period(%{"period" => "last_7_days"}) do
    today = today_mx()
    {Date.add(today, -6), today}
  end

  defp resolve_period(%{"period" => "last_30_days"}) do
    today = today_mx()
    {Date.add(today, -29), today}
  end

  defp resolve_period(%{"period" => "this_month"}) do
    today = today_mx()
    {%Date{today | day: 1}, today}
  end

  defp resolve_period(%{"period" => "last_90_days"}) do
    today = today_mx()
    {Date.add(today, -89), today}
  end

  defp resolve_period(%{"all_dates" => "true"}) do
    case HelloDoctor.data_date_range() do
      {nil, nil} ->
        today = today_mx()
        {%Date{today | day: 1}, today}

      {earliest, latest} ->
        {%Date{earliest | day: 1}, Enum.max([latest, today_mx()], Date)}
    end
  end

  defp resolve_period(%{"period" => "all_time"}), do: resolve_period(%{"all_dates" => "true"})

  defp resolve_period(%{"start_date" => s, "end_date" => e}) when s != "" and e != "" do
    {:ok, start_date} = Date.from_iso8601(s)
    {:ok, end_date} = Date.from_iso8601(e)
    {start_date, end_date}
  end

  defp resolve_period(_params) do
    today = today_mx()
    {%Date{today | day: 1}, today}
  end

  def update_fx_rate(conn, %{"fx_rate" => rate_str}) do
    case Float.parse(rate_str) do
      {rate, _} when rate > 0 ->
        Settings.set_usd_mxn_rate(rate)

        conn
        |> put_flash(:info, "FX rate updated to #{rate} MXN/USD.")
        |> redirect(to: dp(conn, "/"))

      _ ->
        conn
        |> put_flash(:error, "Invalid rate — must be a positive number.")
        |> redirect(to: dp(conn, "/"))
    end
  end

  def sync_costs(conn, _params) do
    results = BillingSync.sync_all()

    messages =
      Enum.flat_map(results, fn {service, result} ->
        case result do
          {:ok, :not_supported} -> []
          {:ok, %{rows_upserted: n}} -> ["#{service}: #{n} rows synced"]
          {:error, :not_configured} -> ["#{service}: not configured (skipped)"]
          {:error, reason} -> ["#{service}: error — #{inspect(reason)}"]
        end
      end)

    flash_msg =
      if Enum.empty?(messages),
        do: "Nothing to sync.",
        else: Enum.join(messages, " | ")

    conn
    |> put_flash(:info, flash_msg)
    |> redirect(to: dp(conn, "/"))
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.DashboardHTML do
  use LedgrWeb, :html

  import LedgrWeb.CoreComponents

  embed_templates "dashboard_html/*"

  @doc """
  Small period-over-period delta pill for the HelloDoctor dashboard KPIs.

  `current` / `prior` are the same scalar measured in this period and the
  prior equal-length window. `:mode` is `:pct` (relative % change, for
  counts) or `:point` (absolute point change, for rates already in %).
  Renders nothing when `prior` is nil (comparison disabled, e.g. all-time).
  """
  attr :current, :any, default: nil
  attr :prior, :any, default: nil
  attr :mode, :atom, default: :pct

  def hd_delta_chip(assigns) do
    assigns = assign(assigns, :delta, hd_delta(assigns.current, assigns.prior, assigns.mode))

    ~H"""
    <span
      :if={@delta}
      class="inline-flex items-center gap-0.5"
      style={"font-size:0.7rem;font-weight:700;padding:1px 7px;border-radius:20px;#{hd_chip_style(elem(@delta, 0))}"}
      title="vs. previous period of equal length"
    >
      <span style="font-size:0.6rem;line-height:1;">{hd_chip_arrow(elem(@delta, 0))}</span>
      {elem(@delta, 1)}
    </span>
    """
  end

  defp hd_delta(cur, prior, _mode) when is_nil(cur) or is_nil(prior), do: nil

  defp hd_delta(cur, prior, :point) when is_number(cur) and is_number(prior) do
    d = Float.round((cur - prior) * 1.0, 1)

    cond do
      d > 0.05 -> {:up, "+" <> :erlang.float_to_binary(d, decimals: 1) <> "pt"}
      d < -0.05 -> {:down, :erlang.float_to_binary(d, decimals: 1) <> "pt"}
      true -> {:flat, "0pt"}
    end
  end

  defp hd_delta(cur, prior, :pct) when is_number(cur) and is_number(prior) do
    cond do
      prior == 0 and cur == 0 -> {:flat, "0%"}
      prior == 0 -> {:up, "new"}
      true -> hd_pct_chip((cur - prior) / prior * 100)
    end
  end

  defp hd_delta(_, _, _), do: nil

  defp hd_pct_chip(change) do
    rounded = round(change)

    cond do
      rounded > 0 -> {:up, "+#{rounded}%"}
      rounded < 0 -> {:down, "#{rounded}%"}
      true -> {:flat, "0%"}
    end
  end

  defp hd_chip_style(:up), do: "background:#d1fae5;color:#047857;"
  defp hd_chip_style(:down), do: "background:#fee2e2;color:#b91c1c;"
  defp hd_chip_style(:flat), do: "background:#f1f5f9;color:#64748b;"

  defp hd_chip_arrow(:up), do: "▲"
  defp hd_chip_arrow(:down), do: "▼"
  defp hd_chip_arrow(:flat), do: "—"
end
