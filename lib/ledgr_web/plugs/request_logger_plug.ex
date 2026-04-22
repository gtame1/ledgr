defmodule LedgrWeb.Plugs.RequestLoggerPlug do
  @moduledoc """
  Temporary debug plug — logs each request through the pipeline so we can
  pinpoint where 403s originate in production.

  Remove once the root cause is identified.
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    session_csrf = get_session(conn, "_csrf_token")

    # body_params is populated by SafeParser (runs in endpoint before router)
    body_csrf = conn.body_params["_csrf_token"]

    Logger.info(
      "[RequestLogger] #{conn.method} #{conn.request_path} | host=#{conn.host} | " <>
        "session_keys=#{inspect(Map.keys(get_session(conn)))} | " <>
        "session_csrf=#{inspect(session_csrf && String.slice(session_csrf, 0, 8))}... | " <>
        "body_csrf=#{inspect(body_csrf && String.slice(body_csrf, 0, 8))}..."
    )

    register_before_send(conn, fn conn ->
      Logger.info("[RequestLogger] RESPONSE #{conn.status} for #{conn.method} #{conn.request_path} | halted=#{conn.halted}")
      conn
    end)
  end
end
