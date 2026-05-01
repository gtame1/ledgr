defmodule LedgrWeb.Plugs.CSRFProtectionPlug do
  @moduledoc """
  Wraps Plug.CSRFProtection so that an invalid/stale CSRF token redirects
  back to the login page with a friendly message instead of a raw 403.

  Root cause: configure_session(renew: true) on login rotates the session
  (and its _csrf_token), so any login form rendered before that rotation
  carries a now-invalid token. The user just needs to reload the page.
  """

  import Plug.Conn
  import Phoenix.Controller
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    Plug.CSRFProtection.call(conn, Plug.CSRFProtection.init([]))
  rescue
    Plug.CSRFProtection.InvalidCSRFTokenError ->
      Logger.warning(
        "[CSRFProtectionPlug] Stale CSRF token on #{conn.method} #{conn.request_path} — redirecting to login"
      )

      # Derive login path from request path: /app/<slug>/anything -> /app/<slug>/login
      login_path =
        case conn.path_info do
          ["app", slug | _] -> "/app/#{slug}/login"
          _ -> "/"
        end

      conn
      |> put_flash(:error, "Your session expired — please try again.")
      |> redirect(to: login_path)
      |> halt()
  end
end
