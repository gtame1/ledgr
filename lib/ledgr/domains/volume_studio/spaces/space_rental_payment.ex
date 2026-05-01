defmodule Ledgr.Domains.VolumeStudio.Spaces.SpaceRentalPayment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.VolumeStudio.Spaces.SpaceRental

  schema "space_rental_payments" do
    belongs_to :space_rental, SpaceRental

    field :amount_cents, :integer
    field :payment_date, :date
    field :method, :string
    field :note, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [:space_rental_id, :amount_cents, :payment_date, :method, :note])
    |> validate_required([:space_rental_id, :amount_cents, :payment_date])
    |> validate_number(:amount_cents, greater_than: 0)
    |> foreign_key_constraint(:space_rental_id)
  end
end
