defmodule LedgrWeb.Plugs.RawBodyCache do
  @moduledoc """
  Custom body reader for Plug.Parsers that caches the raw request body in
  `conn.assigns.raw_body` before it is parsed.

  Required for Stripe webhook signature verification, which needs the original
  raw body bytes (not the parsed params).

  Plugged in via the `body_reader` option in `LedgrWeb.SafeParser`, which is
  installed for *every* request — so this module gates on the request path
  itself. Caching every body would double the memory cost of an 8 MB product
  image upload for no reason: only the three webhook endpoints below ever read
  the assign back.

  Accumulation is an iolist, converted to a binary once when the final chunk
  arrives. The earlier `acc <> body` was quadratic in the number of chunks.
  """

  # The only routes whose controllers read `conn.assigns.raw_body`. Keep in
  # sync with the webhook scopes in `LedgrWeb.Router`.
  @webhook_paths [
    "/webhooks/stripe",
    "/webhooks/hello-doctor-stripe",
    "/app/aumenta-mi-pension/stripe"
  ]

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      # Terminal chunk: flatten the accumulator into the binary the Stripe
      # signature verifier expects.
      {:ok, body, conn} ->
        {:ok, body, finish(conn, body)}

      # More to come: keep appending to the iolist.
      {:more, body, conn} ->
        {:more, body, accumulate(conn, body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp accumulate(%Plug.Conn{request_path: path} = conn, body) when path in @webhook_paths do
    Plug.Conn.put_private(conn, :ledgr_raw_body_acc, [
      Map.get(conn.private, :ledgr_raw_body_acc, []),
      body
    ])
  end

  defp accumulate(conn, _body), do: conn

  defp finish(%Plug.Conn{request_path: path} = conn, body) when path in @webhook_paths do
    raw = IO.iodata_to_binary([Map.get(conn.private, :ledgr_raw_body_acc, []), body])

    conn
    |> Plug.Conn.put_private(:ledgr_raw_body_acc, [])
    |> Plug.Conn.assign(:raw_body, raw)
  end

  defp finish(conn, _body), do: conn
end
