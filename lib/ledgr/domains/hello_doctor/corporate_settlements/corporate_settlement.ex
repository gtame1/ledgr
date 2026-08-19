defmodule Ledgr.Domains.HelloDoctor.CorporateSettlements.CorporateSettlement do
  @moduledoc """
  One employer payment against one monthly corporate invoice.

  Ledgr-owned. `journal_entry_id` is a historical pointer to the entry a
  settlement used to be recorded as, and is null for anything recorded after
  Hello Doctor stopped posting to the general ledger.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "corporate_settlements" do
    field :account_slug, :string
    field :month, :string
    field :amount_cents, :integer
    field :deposit_code, :string, default: "1010"
    field :settled_on, :date
    field :account_name, :string
    field :journal_entry_id, :integer

    timestamps(type: :utc_datetime)
  end

  @required ~w[account_slug month amount_cents deposit_code settled_on]a
  @optional ~w[account_name journal_entry_id]a

  def changeset(settlement, attrs) do
    settlement
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:amount_cents, greater_than: 0)
    |> unique_constraint([:account_slug, :month])
  end
end
