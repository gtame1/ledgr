defmodule Ledgr.Domains.HelloDoctor.CorporateUsage do
  @moduledoc """
  Per-company usage stats for the corporate mini-dashboard.

  "Usage" = completed corporate consultations (a `consultations` row with
  `payment_source = 'corporate'`, `status = 'completed'`, joined to the
  account by `corporate_account_id`). We bucket by the consultation's
  creation month (`assigned_at`) in Mexico City time.

  Cost is measured as the **doctor fee** — a flat $100 MXN per consultation
  (`ConsultationAccounting.doctor_share_mxn/0`), per product decision. The
  rate the company is billed (`consultation_rate_mxn`) is a separate figure
  shown on the invoice; this dash is about what each delivered consult
  *costs* in doctor payouts.

  Note: bot-owned `consultations` has no `inserted_at`; `assigned_at` is the
  creation timestamp (see the schema). Account ids are bot UUIDs mirrored
  onto the consultation at broadcast.
  """

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor
  alias Ledgr.Domains.HelloDoctor.ConsultationAccounting

  @doc "Flat doctor-fee cost per completed consultation, in MXN."
  def cost_per_consult, do: ConsultationAccounting.doctor_share_mxn()

  @doc """
  Usage summary for one corporate account.

  `account_id` is the bot UUID (`account["id"]`). `member_count` is the
  active employee count, used as the denominator for cost-per-employee.
  `rate` is the company's `consultation_rate_mxn` (what we bill per
  consult) — `nil` for off-platform accounts; drives the invoice figures.

  Returns:

      %{
        member_count: 12,
        cost_per_consult: 100.0,
        rate: 250,                             # nil if off-platform
        uses_consultations?: true,
        total_consults: 34,
        total_cost: 3400.0,
        total_billed: 8500.0,                  # nil if no rate
        current_month: "2026-06",
        current_month_consults: 7,
        current_month_billed: 1750.0,          # nil if no rate — the ongoing invoice
        months_with_usage: 5,
        avg_consults_per_month: 6.8,           # over active months
        avg_cost_per_employee_per_month: 56.67, # over active months
        months: [%{month: "2026-06", label: "Jun 2026", consults: 7,
                   cost: 700.0, cost_per_employee: 58.33, billed: 1750.0}, ...]
      }
  """
  def summary(account_id, member_count, rate \\ nil)

  def summary(account_id, member_count, rate) when is_binary(account_id) do
    rate = normalize_rate(rate)
    rows = monthly_rows(account_id, member_count, rate)

    total_consults = Enum.reduce(rows, 0, &(&1.consults + &2))
    total_cost = total_consults * cost_per_consult()
    months_with_usage = length(rows)

    avg_consults_per_month =
      if months_with_usage > 0, do: total_consults / months_with_usage, else: 0.0

    avg_cost_per_month =
      if months_with_usage > 0, do: total_cost / months_with_usage, else: 0.0

    avg_cost_per_employee_per_month =
      if member_count > 0, do: avg_cost_per_month / member_count, else: 0.0

    current_month = current_mx_month()
    current_row = Enum.find(rows, &(&1.month == current_month))
    current_month_consults = if current_row, do: current_row.consults, else: 0

    %{
      member_count: member_count,
      cost_per_consult: cost_per_consult(),
      rate: rate,
      uses_consultations?: total_consults > 0,
      total_consults: total_consults,
      total_cost: total_cost,
      total_billed: rate && total_consults * rate * 1.0,
      current_month: current_month,
      current_month_label: month_label(current_month),
      current_month_consults: current_month_consults,
      current_month_billed: rate && current_month_consults * rate * 1.0,
      months_with_usage: months_with_usage,
      avg_consults_per_month: Float.round(avg_consults_per_month, 1),
      avg_cost_per_month: Float.round(avg_cost_per_month, 2),
      avg_cost_per_employee_per_month: Float.round(avg_cost_per_employee_per_month, 2),
      months: rows
    }
  end

  def summary(_account_id, _member_count, rate) do
    rate = normalize_rate(rate)

    %{
      member_count: 0,
      cost_per_consult: cost_per_consult(),
      rate: rate,
      uses_consultations?: false,
      total_consults: 0,
      total_cost: 0.0,
      total_billed: rate && 0.0,
      current_month: current_mx_month(),
      current_month_label: month_label(current_mx_month()),
      current_month_consults: 0,
      current_month_billed: rate && 0.0,
      months_with_usage: 0,
      avg_consults_per_month: 0.0,
      avg_cost_per_month: 0.0,
      avg_cost_per_employee_per_month: 0.0,
      months: []
    }
  end

  # Current month in Mexico City time, as "YYYY-MM".
  defp current_mx_month, do: Calendar.strftime(HelloDoctor.today(), "%Y-%m")

  # Coerce the bot's rate (integer, string, or nil) to a positive number or nil.
  defp normalize_rate(n) when is_number(n) and n > 0, do: n

  defp normalize_rate(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp normalize_rate(_), do: nil

  # One row per month with ≥1 completed corporate consult, newest first.
  defp monthly_rows(account_id, member_count, rate) do
    sql = """
    SELECT
      to_char(
        date_trunc('month', (assigned_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Mexico_City')),
        'YYYY-MM'
      ) AS month,
      COUNT(*) AS consults
    FROM consultations
    WHERE payment_source = 'corporate'
      AND corporate_account_id = $1
      AND status = 'completed'
      AND assigned_at IS NOT NULL
    GROUP BY month
    ORDER BY month DESC
    """

    %{rows: rows} = Ecto.Adapters.SQL.query!(Repo.active_repo(), sql, [account_id])

    Enum.map(rows, fn [month, consults] ->
      cost = consults * cost_per_consult()

      cost_per_employee =
        if member_count > 0, do: Float.round(cost / member_count, 2), else: 0.0

      %{
        month: month,
        label: month_label(month),
        consults: consults,
        cost: cost,
        cost_per_employee: cost_per_employee,
        billed: rate && consults * rate * 1.0
      }
    end)
  end

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  defp month_label(<<year::binary-4, "-", mm::binary-2>>) do
    case Integer.parse(mm) do
      {n, _} when n in 1..12 -> "#{Enum.at(@months, n - 1)} #{year}"
      _ -> "#{year}-#{mm}"
    end
  end

  defp month_label(other), do: to_string(other)
end
