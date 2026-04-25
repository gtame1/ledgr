defmodule Ledgr.Receipts do
  @moduledoc """
  File I/O for expense receipts and documents.

  In development, files are saved to `priv/static/uploads/receipts/` and served
  as static assets via Plug.Static. In production (Render), they go into the
  persistent disk volume (`UPLOAD_VOLUME/uploads/receipts/`).

  Returns a stored_path like `receipts/uuid.pdf` — always relative to the
  uploads root so the URL `/uploads/receipts/uuid.pdf` resolves regardless
  of environment.
  """

  @allowed_types ~w(
    image/jpeg image/png image/webp image/heic
    application/pdf
    image/gif
    application/octet-stream
  )

  @allowed_extensions ~w(.jpg .jpeg .png .webp .heic .gif .pdf)

  @max_size_bytes 20 * 1024 * 1024  # 20 MB

  @doc """
  Saves a `Plug.Upload` into the receipts directory.

  Returns `{:ok, stored_path}` on success or `{:error, reason}` on failure.
  `stored_path` is relative to the uploads root, e.g. `receipts/abc123.jpg`.
  """
  def save(%Plug.Upload{} = upload) do
    type_check =
      if upload.content_type in [nil, "application/octet-stream"] do
        validate_extension(upload.filename)
      else
        validate_type(upload.content_type)
      end

    with :ok <- type_check,
         :ok <- validate_size(upload.path) do
      dir = receipts_dir()
      File.mkdir_p!(dir)

      ext = upload.filename |> Path.extname() |> String.downcase()
      stored_name = Ecto.UUID.generate() <> ext
      dest = Path.join(dir, stored_name)

      case File.cp(upload.path, dest) do
        :ok -> {:ok, "receipts/#{stored_name}"}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def save(_), do: {:error, :invalid_upload}

  @doc """
  Deletes a receipt from disk given its stored_path (e.g. `receipts/abc.pdf`).
  Safe to call if the file no longer exists.
  """
  def delete("receipts/" <> filename) do
    path = Path.join(receipts_dir(), filename)

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def delete(_), do: :ok

  @doc "Returns the public URL path for a stored_path, e.g. `/uploads/receipts/abc.pdf`."
  def url_for("receipts/" <> _ = stored_path), do: "/uploads/#{stored_path}"
  def url_for(_), do: nil

  # ── Private ────────────────────────────────────────────────

  defp validate_type(nil), do: {:error, "File type could not be determined"}
  defp validate_type(type) do
    if type in @allowed_types, do: :ok, else: {:error, "File type #{inspect(type)} is not allowed. Upload a JPG, PNG, PDF, or WebP."}
  end

  defp validate_extension(filename) do
    ext = filename |> Path.extname() |> String.downcase()
    if ext in @allowed_extensions, do: :ok, else: {:error, "File extension #{ext} is not allowed. Upload a JPG, PNG, PDF, or WebP."}
  end

  defp validate_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_size_bytes -> :ok
      {:ok, %{size: _}} -> {:error, "File is too large. Maximum size is 20 MB."}
      _ -> :ok
    end
  end

  defp receipts_dir do
    base =
      Application.get_env(:ledgr, :upload_serve_dir) ||
        Application.app_dir(:ledgr, "priv/static/uploads")

    Path.join(base, "receipts")
  end
end
