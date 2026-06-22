defmodule LedgrWeb.Domains.HelloDoctor.DoctorNewsController do
  @moduledoc """
  "Doctor News Blast" admin screen + server-side proxy.

  Lets an operator compose a one-shot announcement and send it to doctors over
  WhatsApp through the bot's pre-approved template. The bot owns the actual
  send; we only render the compose UI and proxy two calls to
  `POST /admin/doctors/broadcast-news`:

    * `preview/2` — `dry_run: true`, returns the (redacted) recipient list
    * `send/2`    — `dry_run: false`, performs the irreversible blast

  Why a proxy: the admin API key can blast every doctor, so it must never
  reach the browser. The browser posts JSON here (no key); we attach
  `X-API-Key` from server-side config (`HELLO_DOCTOR_BOT_ADMIN_API_KEY`) and
  hand the bot's response back. `dry_run` is fixed by the route, never taken
  from the client, so a "preview" can't accidentally send.
  """
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.{BotAdmin, Doctors}

  @max_len 1000

  def index(conn, _params) do
    render(conn, :index, specialties: Doctors.specialty_options())
  end

  # dry_run is pinned by the action, not the request body.
  def preview(conn, params), do: proxy(conn, params, true)
  def send(conn, params), do: proxy(conn, params, false)

  defp proxy(conn, params, dry_run) do
    message = params |> Map.get("message", "") |> to_string() |> String.trim()

    cond do
      message == "" ->
        # Mirror the bot's 400 contract without a round-trip.
        conn |> put_status(400) |> json(%{detail: "message must not be empty"})

      String.length(message) > @max_len ->
        conn |> put_status(400) |> json(%{detail: "message exceeds #{@max_len} characters"})

      true ->
        case BotAdmin.broadcast_doctor_news(message, build_filters(params), dry_run) do
          # Pass the bot's status + body straight through; the browser branches
          # on it (400 → inline on message, 401/422 → key misconfig).
          {:ok, status, body} ->
            conn |> put_status(status) |> json(body)

          {:error, :config, reason} ->
            conn |> put_status(503) |> json(%{error: "config", detail: reason})

          {:error, :network, reason} ->
            conn |> put_status(502) |> json(%{error: "network", detail: reason})
        end
    end
  end

  # Only include filters that actually narrow: a blank specialty or an
  # unchecked box is omitted (= no narrowing), matching the bot's defaults.
  defp build_filters(params) do
    specialty = params |> Map.get("specialty", "") |> to_string() |> String.trim()

    %{}
    |> maybe_put(:specialty, if(specialty == "", do: nil, else: specialty))
    |> maybe_put(:available_only, truthy(params["available_only"]))
    |> maybe_put(:terms_accepted_only, truthy(params["terms_accepted_only"]))
    |> maybe_put(:direct_only, truthy(params["direct_only"]))
    |> maybe_put(:exclude_deactivated, truthy(params["exclude_deactivated"]))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, false), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp truthy(v), do: v in [true, "true", "on", "1", 1]
end

defmodule LedgrWeb.Domains.HelloDoctor.DoctorNewsHTML do
  use LedgrWeb, :html

  embed_templates "doctor_news_html/*"
end
