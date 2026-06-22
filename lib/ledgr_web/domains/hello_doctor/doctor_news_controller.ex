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

  # Per-doctor selection: fields we expose to the browser. `phone` is
  # deliberately excluded — the roster returns full numbers and they must
  # never reach the client.
  @doctor_fields [
    "id",
    "name",
    "specialty",
    "is_available",
    "accepts_video_calls",
    "terms_accepted",
    "is_direct",
    "deactivated_at"
  ]

  def index(conn, _params) do
    render(conn, :index, specialties: Doctors.specialty_options())
  end

  @doc """
  Roster for the hand-pick checklist. Proxies the bot's `GET /admin/doctors`
  and returns a trimmed list — `id`/`name`/`specialty` + status flags, with
  full phone numbers stripped server-side.
  """
  def recipients(conn, _params) do
    case BotAdmin.list_doctors() do
      {:ok, doctors} when is_list(doctors) ->
        json(conn, %{doctors: Enum.map(doctors, &trim_doctor/1)})

      {:ok, _other} ->
        conn
        |> put_status(502)
        |> json(%{error: "bad_shape", detail: "unexpected roster response"})

      {:error, reason} ->
        conn |> put_status(502) |> json(%{error: "fetch", detail: to_string(reason)})
    end
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

  # Two mutually-exclusive audience modes. Hand-picked doctor_ids win: when
  # present we send *only* the explicit list and omit the attribute filters, so
  # the recipient set is unambiguous regardless of the bot's precedence rules.
  # Otherwise we fall back to the attribute filters, including only those that
  # actually narrow (blank specialty / unchecked box = omitted).
  defp build_filters(params) do
    case parse_ids(params["doctor_ids"]) do
      [] ->
        specialty = params |> Map.get("specialty", "") |> to_string() |> String.trim()

        %{}
        |> maybe_put(:specialty, if(specialty == "", do: nil, else: specialty))
        |> maybe_put(:available_only, truthy(params["available_only"]))
        |> maybe_put(:terms_accepted_only, truthy(params["terms_accepted_only"]))
        |> maybe_put(:direct_only, truthy(params["direct_only"]))
        |> maybe_put(:exclude_deactivated, truthy(params["exclude_deactivated"]))

      ids ->
        %{doctor_ids: ids}
    end
  end

  defp parse_ids(list) when is_list(list) do
    list |> Enum.map(&to_string/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp parse_ids(_), do: []

  defp trim_doctor(doctor) when is_map(doctor), do: Map.take(doctor, @doctor_fields)
  defp trim_doctor(_), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, false), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp truthy(v), do: v in [true, "true", "on", "1", 1]
end

defmodule LedgrWeb.Domains.HelloDoctor.DoctorNewsHTML do
  use LedgrWeb, :html

  embed_templates "doctor_news_html/*"
end
