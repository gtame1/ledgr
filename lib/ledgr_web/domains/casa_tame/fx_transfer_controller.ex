defmodule LedgrWeb.Domains.CasaTame.FxTransferController do
  @moduledoc """
  Handles cross-currency transfers (MXN <-> USD) with exchange rate recording.
  Creates a journal entry with different amounts on each side.
  """
  use LedgrWeb, :controller

  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.Account
  alias LedgrWeb.Helpers.MoneyHelper

  def new(conn, _params) do
    render(conn, :new,
      usd_account_options: account_options_for("USD"),
      mxn_account_options: account_options_for("MXN"),
      today: Ledgr.Domains.CasaTame.today()
    )
  end

  def create(conn, %{"fx_transfer" => params}) do
    from_account_id = parse_int(params["from_account_id"])
    to_account_id = parse_int(params["to_account_id"])
    from_amount_cents = MoneyHelper.pesos_to_cents(params["from_amount"])
    to_amount_cents = MoneyHelper.pesos_to_cents(params["to_amount"])
    date = parse_date(params["date"]) || Ledgr.Domains.CasaTame.today()
    note = params["note"] || ""

    cond do
      is_nil(from_account_id) or is_nil(to_account_id) ->
        conn
        |> put_flash(:error, "Please select both accounts.")
        |> redirect(to: dp(conn, "/fx-transfers/new"))

      from_amount_cents <= 0 or to_amount_cents <= 0 ->
        conn
        |> put_flash(:error, "Both amounts must be greater than zero.")
        |> redirect(to: dp(conn, "/fx-transfers/new"))

      true ->
        from_account = Accounting.get_account!(from_account_id)
        to_account = Accounting.get_account!(to_account_id)

        # FX rate for description
        rate = from_amount_cents / max(to_amount_cents, 1)
        rate_str = :erlang.float_to_binary(rate, decimals: 4)

        description =
          if note != "",
            do: "FX Transfer: #{note} (rate: #{rate_str})",
            else: "FX Transfer (rate: #{rate_str})"

        # Journal entry: DR destination (to_amount), CR source (from_amount)
        # The amounts differ because of the exchange rate — this is correct FX accounting
        lines = [
          %{
            account_id: to_account_id,
            debit_cents: to_amount_cents,
            credit_cents: 0,
            description: "FX transfer to #{to_account.name}"
          },
          %{
            account_id: from_account_id,
            debit_cents: 0,
            credit_cents: from_amount_cents,
            description: "FX transfer from #{from_account.name}"
          }
        ]

        case Accounting.create_journal_entry_with_lines(
               %{date: date, entry_type: "internal_transfer", description: description},
               lines
             ) do
          {:ok, _je} ->
            conn
            |> put_flash(:info, "FX transfer recorded (rate: #{rate_str}).")
            |> redirect(to: dp(conn, "/transfers"))

          {:error, _} ->
            conn
            |> put_flash(:error, "Failed to record FX transfer.")
            |> redirect(to: dp(conn, "/fx-transfers/new"))
        end
    end
  end

  # Cash & bank accounts filtered by code range
  defp account_options_for("USD") do
    Repo.all(from a in Account, where: a.code >= "1000" and a.code <= "1019", order_by: a.code)
    |> Enum.map(&{&1.name, &1.id})
  end

  defp account_options_for("MXN") do
    Repo.all(from a in Account, where: a.code >= "1100" and a.code <= "1119", order_by: a.code)
    |> Enum.map(&{&1.name, &1.id})
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(str), do: String.to_integer(str)

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(str), do: Date.from_iso8601!(str)
end

defmodule LedgrWeb.Domains.CasaTame.FxTransferHTML do
  use LedgrWeb, :html

  embed_templates "fx_transfer_html/*"
end
