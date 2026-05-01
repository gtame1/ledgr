defmodule Ledgr.Domain.DashboardProvider do
  @moduledoc """
  Behaviour for domain-specific dashboard metrics.

  Each business type implements this to provide its own KPIs and
  operational metrics for the dashboard view.
  """

  @doc "Returns domain-specific metrics for the dashboard within a date range."
  @callback dashboard_metrics(Date.t(), Date.t()) :: map()

  @doc "Count of delivered orders within a date range. Domains without orders return 0."
  @callback delivered_order_count(Date.t(), Date.t()) :: integer()

  @doc "Unit economics for a single product/service."
  @callback unit_economics(integer(), Date.t(), Date.t()) :: map() | nil

  @doc "Unit economics for all products/services."
  @callback all_unit_economics(Date.t(), Date.t()) :: [map()]

  @doc "Options for product/service select dropdowns: [{label, id}]."
  @callback product_select_options() :: [{String.t(), integer()}]

  @doc "Earliest and latest date across all domain data (for date range pickers)."
  @callback data_date_range() :: {Date.t() | nil, Date.t() | nil}

  @doc "Run all diagnostic verification checks. Returns a map of check results."
  @callback verification_checks() :: map()
end
