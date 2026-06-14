defmodule LedgrWeb.Domains.HelloDoctor.DashboardController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.BillingSync
  alias Ledgr.Core.Settings

  def update_fx_rate(conn, %{"fx_rate" => rate_str}) do
    case Float.parse(rate_str) do
      {rate, _} when rate > 0 ->
        Settings.set_usd_mxn_rate(rate)

        conn
        |> put_flash(:info, "FX rate updated to #{rate} MXN/USD.")
        |> redirect(to: dp(conn, "/"))

      _ ->
        conn
        |> put_flash(:error, "Invalid rate — must be a positive number.")
        |> redirect(to: dp(conn, "/"))
    end
  end

  def sync_costs(conn, _params) do
    results = BillingSync.sync_all()

    messages =
      Enum.flat_map(results, fn {service, result} ->
        case result do
          {:ok, :not_supported} -> []
          {:ok, %{rows_upserted: n}} -> ["#{service}: #{n} rows synced"]
          {:error, :not_configured} -> ["#{service}: not configured (skipped)"]
          {:error, reason} -> ["#{service}: error — #{inspect(reason)}"]
        end
      end)

    flash_msg =
      if Enum.empty?(messages),
        do: "Nothing to sync.",
        else: Enum.join(messages, " | ")

    conn
    |> put_flash(:info, flash_msg)
    |> redirect(to: dp(conn, "/"))
  end
end
