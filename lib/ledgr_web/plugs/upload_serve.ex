defmodule LedgrWeb.UploadServe do
  @moduledoc """
  Serves user-uploaded product images from a configurable filesystem path.

  In production (Render), `UPLOAD_VOLUME` is set to the persistent disk mount
  point (e.g., `/var/data`), and this plug serves `/uploads/...` requests from
  that directory so images survive redeployments.

  In development, `upload_serve_dir` is not configured, so this plug is a no-op
  and the normal `Plug.Static` handler serves files from `priv/static/uploads/`.

  NOTE: Logic is intentionally in `call/2`, not `init/1`. Phoenix calls `init/1`
  at compile time in production (during `mix release`), before runtime env vars
  like `UPLOAD_VOLUME` are available. Reading the config at request time ensures
  we always see the value set by `runtime.exs`.
  """

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:ledgr, :upload_serve_dir) do
      nil ->
        conn

      dir ->
        conn
        |> Plug.Static.call(Plug.Static.init(at: "/uploads", from: dir))
    end
  end
end
