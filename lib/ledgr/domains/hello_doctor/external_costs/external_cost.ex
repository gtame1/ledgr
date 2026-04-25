defmodule Ledgr.Domains.HelloDoctor.ExternalCosts.ExternalCost do
  use Ecto.Schema
  import Ecto.Changeset

  schema "external_costs" do
    field :service,      :string
    field :date,         :date
    field :amount_usd,   :float, default: 0.0
    field :units,        :float
    field :unit_type,    :string
    field :model,        :string
    field :raw_response, :map
    field :synced_at,    :utc_datetime

    timestamps()
  end

  @required ~w[service date amount_usd synced_at]a
  @optional ~w[units unit_type model raw_response]a

  def changeset(cost, attrs) do
    cost
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
  end
end
