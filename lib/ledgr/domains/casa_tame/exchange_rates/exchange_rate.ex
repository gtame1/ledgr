defmodule Ledgr.Domains.CasaTame.ExchangeRates.ExchangeRate do
  use Ecto.Schema
  import Ecto.Changeset

  schema "exchange_rates" do
    field :date, :date
    field :from_currency, :string, default: "USD"
    field :to_currency, :string, default: "MXN"
    field :rate, :decimal
    field :source, :string, default: "manual"

    timestamps()
  end

  def changeset(rate, attrs) do
    rate
    |> cast(attrs, [:date, :from_currency, :to_currency, :rate, :source])
    |> validate_required([:date, :rate])
    |> unique_constraint([:date, :from_currency, :to_currency])
  end
end
