defmodule Ledgr.Domains.VolumeStudio.Spaces.SpaceRental do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.VolumeStudio.Spaces.Space
  alias Ledgr.Core.Customers.Customer

  schema "space_rentals" do
    belongs_to :space, Space
    belongs_to :customer, Customer

    field :renter_name, :string
    field :renter_phone, :string
    field :renter_email, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :status, :string, default: "confirmed"
    field :amount_cents, :integer
    field :iva_cents, :integer, default: 0
    field :paid_at, :date
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:space_id, :renter_name, :amount_cents]
  @optional_fields [:customer_id, :renter_phone, :renter_email, :starts_at, :ends_at,
                    :status, :iva_cents, :paid_at, :notes]

  @valid_statuses ~w(confirmed active completed cancelled)

  def changeset(rental, attrs) do
    rental
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_number(:iva_cents, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:space_id)
    |> foreign_key_constraint(:customer_id, on_delete: :nilify_all)
  end

  @doc "Total amount including IVA"
  def total_cents(%__MODULE__{} = r) do
    r.amount_cents + r.iva_cents
  end

  @doc "Whether this rental has been paid"
  def paid?(%__MODULE__{paid_at: nil}), do: false
  def paid?(%__MODULE__{}), do: true
end
