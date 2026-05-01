defmodule LedgrWeb.Storefront.MenuHTML do
  use LedgrWeb, :html

  embed_templates "menu_html/*"

  @doc "Format price in cents as MXN currency string"
  def format_price(cents) when is_integer(cents) do
    pesos = cents / 100
    "$#{:erlang.float_to_binary(pesos, decimals: 2)} MXN"
  end

  def format_price(_), do: ""

  @doc "Strip markdown formatting from text, returning plain text suitable for previews."
  def strip_markdown(nil), do: ""
  def strip_markdown(""), do: ""

  def strip_markdown(text) do
    text
    # Headings: ## Title -> Title
    |> then(&Regex.replace(~r/^\#{1,6}\s+/m, &1, ""))
    # Bold/italic: **x**, __x__, *x*, _x_ -> x
    |> then(&Regex.replace(~r/(\*{1,2}|_{1,2})(.+?)\1/, &1, "\\2"))
    # Inline code: `x` -> x
    |> then(&Regex.replace(~r/`([^`]+)`/, &1, "\\1"))
    # Links: [text](url) -> text
    |> then(&Regex.replace(~r/\[([^\]]+)\]\([^\)]+\)/, &1, "\\1"))
    # Images: ![alt](url) -> alt
    |> then(&Regex.replace(~r/!\[([^\]]*)\]\([^\)]+\)/, &1, "\\1"))
    # Blockquotes: > text -> text
    |> then(&Regex.replace(~r/^>\s*/m, &1, ""))
    # List bullets: - item or * item or 1. item -> item
    |> then(&Regex.replace(~r/^(\s*[-*]|\s*\d+\.)\s+/m, &1, ""))
    # Horizontal rules
    |> then(&Regex.replace(~r/^[-*_]{3,}\s*$/m, &1, ""))
    # Collapse multiple newlines/spaces into a single space
    |> then(&Regex.replace(~r/\s+/, &1, " "))
    |> String.trim()
  end

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
