defmodule LedgrWeb.Storefront.MenuHTML do
  use LedgrWeb, :html

  embed_templates "menu_html/*"

  @doc "Format price in cents as MXN currency string"
  def format_price(cents) when is_integer(cents) do
    pesos = cents / 100
    "$#{:erlang.float_to_binary(pesos, decimals: 2)} MXN"
  end

  def format_price(_), do: ""

  @doc "Truncate text to a maximum length, appending ellipsis if needed"
  def truncate(nil, _max), do: ""
  def truncate(text, max) when byte_size(text) <= max, do: text
  def truncate(text, max) do
    String.slice(text, 0, max) <> "..."
  end

  @doc """
  Builds a flat list of all image URLs for a product.
  Starts with the thumbnail (image_url) then appends gallery images.
  """
  def build_all_images(product) do
    thumbnail = if product.image_url, do: [product.image_url], else: []
    gallery = Enum.map(product.images || [], & &1.image_url)
    thumbnail ++ gallery
  end

  @doc "Render a markdown string as safe HTML. Returns empty string for nil/empty input."
  def render_markdown(nil), do: Phoenix.HTML.raw("")
  def render_markdown(""), do: Phoenix.HTML.raw("")

  def render_markdown(text) do
    text
    |> Earmark.as_html!(%Earmark.Options{compact_output: true})
    |> Phoenix.HTML.raw()
  end
end
