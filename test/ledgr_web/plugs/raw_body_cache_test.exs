defmodule LedgrWeb.Plugs.RawBodyCacheTest do
  @moduledoc """
  The raw request body is cached only for the three Stripe webhook endpoints.
  Caching it on every request duplicated each body in `conn.assigns` on top of
  the parser's own copy — for an 8 MB upload limit, applied app-wide — and
  accumulated it with `<>`, which is quadratic in the chunk count.

  These tests pin both halves: webhook paths still get a byte-exact body
  (Stripe signature verification fails otherwise), and nothing else retains one.

  They drive `LedgrWeb.SafeParser` directly rather than dispatching through a
  controller, so what is under test is the parser wiring itself — the same
  `init/1` options the endpoint installs — and not whatever the webhook
  controller decides to do with an unsigned payload.
  """
  use ExUnit.Case, async: true

  @webhook_paths [
    "/webhooks/stripe",
    "/webhooks/hello-doctor-stripe",
    "/app/aumenta-mi-pension/stripe"
  ]

  @opts LedgrWeb.SafeParser.init([])

  defp parse(path, body) do
    :post
    |> Plug.Test.conn(path, body)
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> LedgrWeb.SafeParser.call(@opts)
  end

  describe "webhook paths" do
    test "cache the raw body verbatim" do
      body = ~s({"id":"evt_123","type":"checkout.session.completed"})

      for path <- @webhook_paths do
        conn = parse(path, body)

        assert conn.assigns[:raw_body] == body,
               "#{path} did not cache an exact raw body — Stripe signature verification would fail"
      end
    end

    test "reassemble a body large enough to arrive in several chunks" do
      big = ~s({"pad":") <> String.duplicate("a", 500_000) <> ~s("})

      conn = parse("/webhooks/hello-doctor-stripe", big)

      assert conn.assigns[:raw_body] == big
      assert byte_size(conn.assigns[:raw_body]) == byte_size(big)
    end

    test "still parse params as usual" do
      conn = parse("/webhooks/stripe", ~s({"id":"evt_1"}))

      assert conn.params["id"] == "evt_1"
    end
  end

  describe "every other route" do
    test "does not retain the request body" do
      for path <- ["/mr-munch-me/cart/add", "/app/hello-doctor/expenses", "/login"] do
        conn = parse(path, ~s({"a":1}))

        refute conn.assigns[:raw_body],
               "#{path} cached its body; that is the duplication this plug gates against"
      end
    end

    test "leaves no accumulator behind in conn.private" do
      conn = parse("/mr-munch-me/cart/add", ~s({"a":1}))

      refute Map.get(conn.private, :ledgr_raw_body_acc)
      assert conn.params["a"] == 1
    end
  end
end
