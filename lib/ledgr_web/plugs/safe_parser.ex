defmodule LedgrWeb.SafeParser do
  @moduledoc """
  A Plug.Parsers wrapper that handles oversized request bodies gracefully.

  When an upload exceeds the 8 MB limit, `Plug.Parsers` raises
  `RequestTooLargeError`. This plug catches that exception and returns a
  user-friendly 413 page with a back-link instead of crashing with a 500.
  """

  @behaviour Plug

  # 8 MB — matches the client-side validation in product upload forms
  @max_bytes 8_000_000

  def init(_opts) do
    Plug.Parsers.init(
      parsers: [:urlencoded, :multipart, :json],
      pass: ["*/*"],
      json_decoder: Phoenix.json_library(),
      length: @max_bytes
    )
  end

  def call(conn, opts) do
    Plug.Parsers.call(conn, opts)
  rescue
    Plug.Parsers.RequestTooLargeError ->
      body = """
      <!DOCTYPE html>
      <html>
      <head><title>File Too Large</title></head>
      <body style="font-family: sans-serif; padding: 2rem; max-width: 480px; margin: 4rem auto;">
        <h2 style="color: #b91c1c;">Image too large</h2>
        <p>The file you uploaded exceeds the 8 MB limit. Please choose a smaller image and try again.</p>
        <p><a href="javascript:history.back()" style="color: #2563eb;">&larr; Go back</a></p>
      </body>
      </html>
      """

      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(413, body)
      |> Plug.Conn.halt()
  end
end
