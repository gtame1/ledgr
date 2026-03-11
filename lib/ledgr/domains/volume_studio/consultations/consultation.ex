defmodule Ledgr.Domains.VolumeStudio.Consultations.Consultation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Customers.Customer
  alias Ledgr.Domains.VolumeStudio.Instructors.Instructor

  schema "consultations" do
    belongs_to :customer, Customer
    belongs_to :instructor, Instructor

    field :scheduled_at, :utc_datetime
    field :duration_minutes, :integer, default: 60
    field :status, :string, default: "scheduled"
    field :notes, :string
    field :amount_cents, :integer
    field :iva_cents, :integer, default: 0
    field :paid_at, :date

    timestamps(type: :utc_datetime)
  end

  @required_fields [:customer_id, :instructor_id, :amount_cents, :scheduled_at]
  @optional_fields [:duration_minutes, :status, :notes, :iva_cents, :paid_at]

  @valid_statuses ~w(scheduled completed cancelled no_show)

  def changeset(consultation, attrs) do
    consultation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_number(:iva_cents, greater_than_or_equal_to: 0)
    |> validate_number(:duration_minutes, greater_than: 0)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:instructor_id)
  end

  @doc "Total amount including IVA"
  def total_cents(%__MODULE__{} = c) do
    c.amount_cents + c.iva_cents
  end

  @doc "Whether this consultation has been paid"
  def paid?(%__MODULE__{paid_at: nil}), do: false
  def paid?(%__MODULE__{}), do: true
end
