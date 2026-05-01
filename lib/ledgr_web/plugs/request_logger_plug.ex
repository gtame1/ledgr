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

    # body_params access is safe only after SafeParser (runs in endpoint) — guard defensively
    body_csrf =
      case conn.body_params do
        %Plug.Conn.Unfetched{} -> :unfetched
        params when is_map(params) -> Map.get(params, "_csrf_token")
      end

    Logger.info(
      "[RequestLogger] #{conn.method} #{conn.request_path} | host=#{conn.host} | " <>
        "session_keys=#{inspect(Map.keys(get_session(conn)))} | " <>
        "session_csrf=#{inspect(session_csrf && String.slice(session_csrf, 0, 8))}... | " <>
        "body_csrf=#{inspect(if is_binary(body_csrf), do: String.slice(body_csrf, 0, 8), else: body_csrf)}..."
    )

    register_before_send(conn, fn conn ->
      Logger.info(
        "[RequestLogger] RESPONSE #{conn.status} for #{conn.method} #{conn.request_path} | halted=#{conn.halted}"
      )

      conn
    end)
  end
end
