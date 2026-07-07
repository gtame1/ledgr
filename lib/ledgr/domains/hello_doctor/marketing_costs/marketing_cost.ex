defmodule Ledgr.Domains.HelloDoctor.MarketingCosts.MarketingCost do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  A marketing / ad spend line — one platform's spend for one date (CSV-fed
  today). Posts to the GL via `MarketingCostAccounting`. See the
  `create_marketing_costs` migration for column semantics.
  """

  schema "marketing_costs" do
    field :platform, :string
    field :date, :date
    field :amount, :float, default: 0.0
    field :currency, :string, default: "MXN"
    field :fx_rate, :float
    field :spend_mxn_cents, :integer
    field :description, :string
    field :source, :string, default: "csv"
    field :campaign_id, :string
    # GL posting
    field :posted_at, :utc_datetime
    field :journal_entry_id, :integer

    timestamps()
  end

  @required ~w[platform date amount currency]a
  @optional ~w[fx_rate spend_mxn_cents description source campaign_id posted_at journal_entry_id]a

  def changeset(cost, attrs) do
    cost
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:amount, greater_than_or_equal_to: 0)
    |> update_change(:platform, &normalize/1)
    |> update_change(:currency, &normalize_currency/1)
  end

  defp normalize(nil), do: nil
  defp normalize(s), do: s |> String.trim() |> String.downcase()

  defp normalize_currency(nil), do: "MXN"
  defp normalize_currency(s), do: s |> String.trim() |> String.upcase()
end
