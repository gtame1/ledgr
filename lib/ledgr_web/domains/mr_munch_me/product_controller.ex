defmodule LedgrWeb.Domains.MrMunchMe.ProductController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Orders
  alias Ledgr.Domains.MrMunchMe.Orders.Product
  alias Ledgr.Uploads

  def index(conn, params) do
    sort  = params["sort"]  || "position"
    order = params["order"] || "asc"

    products =
      Orders.list_all_products()
      |> sort_products(sort, order)

    render(conn, :index, products: products, sort: sort, order: order)
  end

  def new(conn, _params) do
    changeset = Orders.change_product(%Product{})
    render(conn, :new,
      changeset: changeset,
      action: dp(conn, "/products")
    )
  end

  def create(conn, %{"product" => product_params} = params) do
    # Handle thumbnail upload if provided
    {product_params, upload_error} = handle_thumbnail_upload(product_params, params)
    conn = if upload_error, do: put_flash(conn, :error, upload_error), else: conn

    case Orders.create_product(product_params) do
      {:ok, product} ->
        conn
        |> put_flash(:info, "Product created. Add variants below, then create a recipe for each variant.")
        |> redirect(to: dp(conn, "/products/#{product.id}/edit"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new,
          changeset: Map.put(changeset, :action, :insert),
          action: dp(conn, "/products")
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    product = Orders.get_product_with_images!(id)
    changeset = Orders.change_product(product)
    render(conn, :edit, product: product, changeset: changeset, action: dp(conn, "/products/#{product.id}"))
  end

  def update(conn, %{"id" => id, "product" => product_params} = params) do
    product = Orders.get_product_with_images!(id)

    # Handle thumbnail upload if provided
    {product_params, upload_error} = handle_thumbnail_upload(product_params, params)
    conn = if upload_error, do: put_flash(conn, :error, upload_error), else: conn

    case Orders.update_product(product, product_params) do
      {:ok, _product} ->
        conn
        |> put_flash(:info, "Product updated successfully.")
        |> redirect(to: dp(conn, "/products"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit, product: product, changeset: Map.put(changeset, :action, :update), action: dp(conn, "/products/#{product.id}"))
    end
  end

  def toggle_active(conn, %{"id" => id}) do
    product = Orders.get_product!(id)

    case Orders.update_product(product, %{active: !product.active}) do
      {:ok, updated} ->
        status = if updated.active, do: "activated", else: "deactivated"

        conn
        |> put_flash(:info, "Product #{status}.")
        |> redirect(to: dp(conn, "/products"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not update product status.")
        |> redirect(to: dp(conn, "/products"))
    end
  end

  def move_up(conn, %{"id" => id}) do
    Orders.get_product!(id) |> Orders.move_product_up()
    redirect(conn, to: dp(conn, "/products"))
  end

  def move_down(conn, %{"id" => id}) do
    Orders.get_product!(id) |> Orders.move_product_down()
    redirect(conn, to: dp(conn, "/products"))
  end

  def delete(conn, %{"id" => id}) do
    {:ok, _} =
      Orders.get_product!(id)
      |> Orders.delete_product()

    conn
    |> put_flash(:info, "Product deleted successfully.")
    |> redirect(to: dp(conn, "/products"))
  end

  def upload_gallery_image(conn, %{"product_id" => product_id, "gallery_image" => %Plug.Upload{} = upload}) do
    product = Orders.get_product!(product_id)

    case Uploads.save(upload) do
      {:ok, url_path} ->
        # Determine next position
        existing_images = Orders.list_product_images(product.id)
        next_position = length(existing_images)

        case Orders.create_product_image(%{
          product_id: product.id,
          image_url: url_path,
          position: next_position
        }) do
          {:ok, _image} ->
            conn
            |> put_flash(:info, "Gallery image uploaded successfully.")
            |> redirect(to: dp(conn, "/products/#{product.id}/edit"))

          {:error, _changeset} ->
            # Clean up the uploaded file if DB insert fails
            Uploads.delete(url_path)

            conn
            |> put_flash(:error, "Failed to save gallery image.")
            |> redirect(to: dp(conn, "/products/#{product.id}/edit"))
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to upload image file.")
        |> redirect(to: dp(conn, "/products/#{product.id}/edit"))
    end
  end

  def upload_gallery_image(conn, %{"product_id" => product_id}) do
    conn
    |> put_flash(:error, "Please select an image file to upload.")
    |> redirect(to: dp(conn, "/products/#{product_id}/edit"))
  end

  def delete_gallery_image(conn, %{"product_id" => product_id, "image_id" => image_id}) do
    image = Orders.get_product_image!(image_id)
    {:ok, _} = Orders.delete_product_image(image)

    conn
    |> put_flash(:info, "Gallery image removed.")
    |> redirect(to: dp(conn, "/products/#{product_id}/edit"))
  end

  # Private helpers

  defp sort_products(products, "position", _), do: products

  defp sort_products(products, "active", "asc"),
    do: Enum.sort_by(products, &{&1.active, String.downcase(&1.name)}, :asc)

  defp sort_products(products, "active", _desc),
    do: Enum.sort_by(products, &{!&1.active, String.downcase(&1.name)}, :asc)

  defp sort_products(products, _name, "desc"),
    do: Enum.sort_by(products, &String.downcase(&1.name), :desc)

  defp sort_products(products, _name, _asc),
    do: Enum.sort_by(products, &String.downcase(&1.name), :asc)

  defp handle_thumbnail_upload(product_params, %{"product" => %{"thumbnail" => %Plug.Upload{} = upload}}) do
    case Uploads.save(upload) do
      {:ok, url_path} ->
        # Delete old uploaded thumbnail if it was a local upload
        old_url = product_params["image_url"]
        if old_url, do: Uploads.delete(old_url)

        {Map.put(product_params, "image_url", url_path), nil}

      {:error, _reason} ->
        {product_params, "Failed to upload image. Please try again."}
    end
  end

  defp handle_thumbnail_upload(product_params, _params), do: {product_params, nil}
end

defmodule LedgrWeb.Domains.MrMunchMe.ProductHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents
  import Phoenix.Naming

  embed_templates "product_html/*"
end
