defmodule LedgrWeb.Helpers.DateTimeHelpers do
  @moduledoc """
  Datetime formatters that render in Mexico City local time.

  All `NaiveDateTime` values are interpreted as UTC (matching how every
  domain in this repo stores them via `timestamps()` / `:naive_datetime`),
  shifted to `America/Mexico_City`, then formatted with `Calendar.strftime/2`.

  ## Usage

      <%= fmt_datetime(c.assigned_at) %>
      <%= fmt_datetime(c.assigned_at, "%b %-d, %Y · %-I:%M %p") %>
      <%= fmt_date(c.created_at) %>
      <%= fmt_time(msg.created_at) %>
  """

  @tz "America/Mexico_City"

  @default_datetime_fmt "%b %d, %Y %I:%M %p"
  @default_date_fmt "%b %d, %Y"
  @default_time_fmt "%I:%M %p"

  def fmt_datetime(value, fmt \\ @default_datetime_fmt)
  def fmt_datetime(nil, _fmt), do: nil

  def fmt_datetime(%NaiveDateTime{} = ndt, fmt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> fmt_datetime(fmt)
  end

  def fmt_datetime(%DateTime{} = dt, fmt) do
    dt
    |> DateTime.shift_zone!(@tz)
    |> Calendar.strftime(fmt)
  end

  def fmt_date(value, fmt \\ @default_date_fmt)
  def fmt_date(nil, _fmt), do: nil
  def fmt_date(%Date{} = d, fmt), do: Calendar.strftime(d, fmt)
  def fmt_date(other, fmt), do: fmt_datetime(other, fmt)

  def fmt_time(value, fmt \\ @default_time_fmt)
  def fmt_time(nil, _fmt), do: nil
  def fmt_time(other, fmt), do: fmt_datetime(other, fmt)
end
