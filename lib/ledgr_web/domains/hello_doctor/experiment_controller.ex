defmodule LedgrWeb.Domains.HelloDoctor.ExperimentController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.Experiments

  # List every registered experiment (the scoreboard).
  def index(conn, _params) do
    render(conn, :index, experiments: Experiments.list_experiments())
  end

  # One experiment: its pre-registered spec + the live per-arm readout.
  def show(conn, %{"id" => id}) do
    case Experiments.get_experiment(id) do
      nil ->
        conn
        |> put_flash(:error, "Unknown experiment: #{id}")
        |> redirect(to: dp(conn, "/experiments"))

      experiment ->
        readout = Experiments.readout(id)
        render(conn, :show, experiment: experiment, readout: readout)
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.ExperimentHTML do
  use LedgrWeb, :html

  embed_templates "experiment_html/*"

  @doc "Colored status pill for an experiment's lifecycle state."
  def exp_status_badge(:dark), do: {"Dark · not launched", "#fef3c7", "#92400e"}
  def exp_status_badge(:running), do: {"Running", "#d1fae5", "#065f46"}
  def exp_status_badge(:concluded), do: {"Concluded", "#e2e8f0", "#334155"}
  def exp_status_badge(_), do: {"—", "var(--bg-secondary)", "var(--text-muted)"}

  @doc "Pull a variant's value for a given key from a readout block, defaulting to 0."
  def cell(rows, variant, key) do
    case Enum.find(rows, &(&1.variant == variant)) do
      nil -> 0
      row -> Map.get(row, key) || 0
    end
  end

  @doc "Distinct variants present in a readout block, control first."
  def variants(rows) do
    rows
    |> Enum.map(& &1.variant)
    |> Enum.uniq()
    |> Enum.sort_by(&(&1 != "control"))
  end

  @doc """
  A number to a percentage-of-max bar width (0–100). Used for the inline SVG /
  div bar charts so no external chart library is needed.
  """
  def bar_pct(_value, 0), do: 0
  def bar_pct(_value, +0.0), do: 0

  def bar_pct(value, max) do
    v = to_num(value)
    m = to_num(max)
    if m <= 0, do: 0, else: min(100.0, Float.round(v / m * 100, 1))
  end

  @doc "Coerce Decimal / integer / float / nil to a float for arithmetic + display."
  def to_num(nil), do: 0.0
  def to_num(%Decimal{} = d), do: Decimal.to_float(d)
  def to_num(n) when is_integer(n), do: n * 1.0
  def to_num(n) when is_float(n), do: n
  def to_num(_), do: 0.0

  @doc "Format a numeric-ish value as an integer string (counts)."
  def int_str(v), do: v |> to_num() |> round() |> Integer.to_string()

  @doc "Format a numeric-ish value as a 1-decimal percentage string."
  def pct_str(v), do: "#{:erlang.float_to_binary(to_num(v) + 0.0, decimals: 1)}%"

  @doc "Human explanation for why a readout is unavailable."
  def not_launched_reason(:no_table),
    do:
      "No enrollments exist yet — the bot creates the experiment_assignments table on " <>
        "the first enrollment. This experiment is registered but dark (treatment not built / not launched)."

  def not_launched_reason(:no_enrollments),
    do: "The experiment is live in the registry but no patients have been enrolled yet."

  def not_launched_reason(_), do: "No readout data available yet."
end
