defmodule LedgrWeb.UploadServe do
  @moduledoc """
  Serves user-uploaded product images from a configurable filesystem path.

  In production (Render), `UPLOAD_VOLUME` is set to the persistent disk mount
  point (e.g., `/var/data`), and this plug serves `/uploads/...` requests from
  that directory so images survive redeployments.

  In development, `upload_serve_dir` is not configured, so this plug is a no-op
  and the normal `Plug.Static` handler serves files from `priv/static/uploads/`.
  """

  @behaviour Plug

  def init(_opts) do
    case Application.get_env(:ledgr, :upload_serve_dir) do
      nil -> :noop
      dir -> Plug.Static.init(at: "/uploads", from: dir)
    end
  end

  def call(conn, :noop), do: conn
  def call(conn, opts), do: Plug.Static.call(conn, opts)
end
