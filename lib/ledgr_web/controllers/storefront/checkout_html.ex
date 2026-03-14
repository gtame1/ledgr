defmodule LedgrWeb.Storefront.CheckoutHTML do
  use LedgrWeb, :html

  embed_templates "checkout_html/*"

  def format_price(cents) when is_integer(cents) do
    pesos = cents / 100
    "$#{:erlang.float_to_binary(pesos, decimals: 2)} MXN"
  end

  def format_price(_), do: ""

  # Formats a delivery date string ("YYYY-MM-DD") or Date struct → "Mar 19, 2026"
  def format_delivery_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> Calendar.strftime(d, "%b %-d, %Y")
      _ -> date
    end
  end

  def format_delivery_date(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")
  def format_delivery_date(nil), do: "—"
  def format_delivery_date(other), do: to_string(other)
end
