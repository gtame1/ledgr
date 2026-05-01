defmodule LedgrWeb.Plugs.LedgrAccessPlug do
  @moduledoc """
  Gates the Ledgr landing page (/ and /apps) behind a simple site password.

  Only fires when the request arrives on the Ledgr platform host (ledgr.mx,
  configurable via LEDGR_HOST). Custom domains (e.g. mrmunchme.com) are
  never gated — they have their own per-app authentication.

  If LEDGR_PASSWORD is not set, the plug is a no-op (no protection).
  """

  import Plug.Conn
  import Phoenix.Controller
  require Logger

  @unlock_path "/unlock"

  # Only these paths require the ledgr site password.
  @protected_paths [[], ["apps"]]

  def init(opts), do: opts

  def call(conn, _opts) do
    password = System.get_env("LEDGR_PASSWORD")

    cond do
      # No password configured — skip protection
      is_nil(password) or password == "" ->
        conn

      # Not on the Ledgr platform host — custom domain, skip entirely
      not ledgr_host?(conn) ->
        conn

      # Only protect the landing page (/) and app picker (/apps)
      conn.path_info not in @protected_paths ->
        conn

      # Already authenticated
      get_session(conn, :ledgr_access) == true ->
        conn

      # Not authenticated — redirect to unlock
      true ->
        Logger.warning("[LedgrAccessPlug] blocking path=#{conn.request_path} host=#{conn.host}")

        conn
        |> put_session(:ledgr_return_to, conn.request_path)
        |> redirect(to: @unlock_path)
        |> halt()
    end
  end

  # Returns true only for the Ledgr platform host and local dev.
  # Any other host (e.g. mrmunchme.com) is treated as a custom domain.
  defp ledgr_host?(conn) do
    host = String.downcase(conn.host)
    ledgr_host = System.get_env("LEDGR_HOST", "ledgr.mx")

    host == ledgr_host or
      host == "www.#{ledgr_host}" or
      String.ends_with?(host, ".onrender.com") or
      host in ["localhost", "127.0.0.1"]
  end
end
