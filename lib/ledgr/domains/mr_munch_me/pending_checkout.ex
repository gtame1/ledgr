defmodule Ledgr.Domains.MrMunchMe.PendingCheckout do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :id

  schema "pending_checkouts" do
    # %{"variant_id_string" => quantity_integer}
    field :cart, :map
    # %{delivery_type, delivery_date, delivery_time, delivery_address, special_instructions}
    field :checkout_attrs, :map

    belongs_to :customer, Ledgr.Core.Customers.Customer

    field :stripe_session_id, :string
    field :processed_at, :naive_datetime
    field :expires_at, :naive_datetime

    timestamps()
  end

  def changeset(pending_checkout, attrs) do
    pending_checkout
    |> cast(attrs, [
      :cart,
      :checkout_attrs,
      :customer_id,
      :stripe_session_id,
      :processed_at,
      :expires_at
    ])
    |> validate_required([:cart, :checkout_attrs, :customer_id, :expires_at])
  end
end
