defmodule Ledgr.Uploads do
  @moduledoc """
  Simple file upload helper for saving product images.

  In development, files are saved to `priv/static/uploads/products/` and served
  as static assets. In production (Render), files are saved to the persistent disk
  volume configured via the `UPLOAD_VOLUME` env var, and served by `LedgrWeb.UploadServe`.

  Returns URL paths relative to `/uploads/products/` regardless of environment.
  """

  @doc """
  Saves a `Plug.Upload` to the filesystem.

  Returns `{:ok, url_path}` where `url_path` is like `/uploads/products/abc123.jpg`.
  """
  def save(%Plug.Upload{path: tmp_path, filename: filename}) do
    dir = upload_dir()
    File.mkdir_p!(dir)

    ext = Path.extname(filename) |> String.downcase()
    safe_name = Ecto.UUID.generate() <> ext
    dest_path = Path.join(dir, safe_name)

    case File.cp(tmp_path, dest_path) do
      :ok ->
        {:ok, "/uploads/products/#{safe_name}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def save(_), do: {:error, :invalid_upload}

  @doc """
  Deletes an uploaded file given its URL path (e.g., `/uploads/products/abc123.jpg`).

  Only deletes files within the uploads directory for safety.
  Returns `:ok` or `{:error, reason}`.
  """
  def delete("/uploads/products/" <> filename) do
    file_path = Path.join(upload_dir(), filename)

    case File.rm(file_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok  # Already deleted, that's fine
      {:error, reason} -> {:error, reason}
    end
  end

  # Don't delete external URLs or paths outside our upload dir
  def delete(_url), do: :ok

  # Returns the filesystem path where uploads are stored.
  # In production: configured via UPLOAD_VOLUME env var → runtime.exs.
  # In development: priv/static/uploads/products (served as static assets).
  defp upload_dir do
    Application.get_env(:ledgr, :upload_dir) ||
      Application.app_dir(:ledgr, "priv/static/uploads/products")
  end
end
