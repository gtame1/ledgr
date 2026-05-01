defmodule LedgrWeb.Storefront.CartController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Orders

  def index(conn, _params) do
    cart = get_session(conn, :cart) || %{}
    {cart_items, cart_total} = load_cart_items(cart)

    conn
    |> assign(:storefront, true)
    |> assign(:page_title, "Your Cart")
    |> render(:index, cart_items: cart_items, cart_total: cart_total)
  end

  def add(conn, %{"variant_id" => variant_id, "quantity" => quantity}) do
    variant_id_str = to_string(variant_id)
    quantity = max(String.to_integer(to_string(quantity)), 1)

    # Verify variant exists and is active
    variant = Orders.get_variant!(String.to_integer(variant_id_str))
    unless variant.active, do: raise("Variant not active")

    cart = get_session(conn, :cart) || %{}
    existing_qty = Map.get(cart, variant_id_str, 0)
    cart = Map.put(cart, variant_id_str, existing_qty + quantity)

    display_name = "#{variant.product.name} · #{variant.name}"

    conn
    |> put_session(:cart, cart)
    |> put_flash(:info, "#{display_name} agregado al carrito!")
    |> redirect(to: "/mr-munch-me/menu")
  end

  def update(conn, %{"variant_id" => variant_id, "quantity" => quantity}) do
    variant_id_str = to_string(variant_id)
    quantity = String.to_integer(to_string(quantity))
    cart = get_session(conn, :cart) || %{}

    cart =
      if quantity <= 0 do
        Map.delete(cart, variant_id_str)
      else
        Map.put(cart, variant_id_str, quantity)
      end

    conn
    |> put_session(:cart, cart)
    |> redirect(to: "/mr-munch-me/cart")
  end

  def remove(conn, %{"variant_id" => variant_id}) do
    variant_id_str = to_string(variant_id)
    cart = get_session(conn, :cart) || %{}
    cart = Map.delete(cart, variant_id_str)

    conn
    |> put_session(:cart, cart)
    |> put_flash(:info, "Producto eliminado del carrito.")
    |> redirect(to: "/mr-munch-me/cart")
  end

  defp load_cart_items(cart) when map_size(cart) == 0, do: {[], 0}

  defp load_cart_items(cart) do
    items =
      Enum.reduce(cart, [], fn {variant_id_str, quantity}, acc ->
        case Integer.parse(variant_id_str) do
          {id, _} ->
            try do
              variant = Orders.get_variant!(id)
              product = variant.product
              subtotal = variant.price_cents * quantity

              [
                %{product: product, variant: variant, quantity: quantity, subtotal: subtotal}
                | acc
              ]
            rescue
              Ecto.NoResultsError -> acc
            end

          :error ->
            acc
        end
      end)
      |> Enum.sort_by(fn item -> "#{item.product.name} #{item.variant.name}" end)

    total = Enum.reduce(items, 0, fn item, acc -> acc + item.subtotal end)
    {items, total}
  end
end
