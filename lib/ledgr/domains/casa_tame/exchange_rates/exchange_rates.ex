defmodule Ledgr.Domains.CasaTame.ExchangeRates do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.CasaTame.ExchangeRates.ExchangeRate

  require Logger

  @doc "Get the most recent cached USD→MXN rate."
  def get_latest_rate do
    from(r in ExchangeRate,
      where: r.from_currency == "USD" and r.to_currency == "MXN",
      order_by: [desc: r.date],
      limit: 1
    )
    |> Repo.one()
  end

  @doc "Get rate for a specific date, falling back to the most recent before it."
  def get_rate_for_date(date) do
    from(r in ExchangeRate,
      where: r.from_currency == "USD" and r.to_currency == "MXN" and r.date <= ^date,
      order_by: [desc: r.date],
      limit: 1
    )
    |> Repo.one()
  end

  @doc "Returns the USD→MXN rate as a float, or a fallback."
  def usd_to_mxn_rate(fallback \\ 20.0) do
    case get_latest_rate() do
      %ExchangeRate{rate: rate} -> Decimal.to_float(rate)
      nil -> fallback
    end
  end

  @doc "Upsert a rate for today."
  def create_or_update_rate(attrs) do
    date = attrs[:date] || attrs["date"] || Ledgr.Domains.CasaTame.today()

    case Repo.get_by(ExchangeRate, date: date, from_currency: "USD", to_currency: "MXN") do
      nil ->
        %ExchangeRate{}
        |> ExchangeRate.changeset(Map.put(attrs, :date, date))
        |> Repo.insert()

      existing ->
        existing
        |> ExchangeRate.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc "Fetch USD→MXN rate from frankfurter.app and cache it."
  def fetch_and_cache_rate do
    case Req.get("https://api.frankfurter.app/latest?from=USD&to=MXN") do
      {:ok, %{status: 200, body: %{"rates" => %{"MXN" => rate}}}} ->
        Logger.info("[CasaTame] Fetched exchange rate: 1 USD = #{rate} MXN")

        create_or_update_rate(%{
          date: Ledgr.Domains.CasaTame.today(),
          from_currency: "USD",
          to_currency: "MXN",
          rate: Decimal.new(to_string(rate)),
          source: "frankfurter.app"
        })

      {:ok, resp} ->
        Logger.warning("[CasaTame] Unexpected exchange rate response: #{inspect(resp.status)}")
        {:error, :unexpected_response}

      {:error, reason} ->
        Logger.warning("[CasaTame] Failed to fetch exchange rate: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
