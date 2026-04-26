defmodule Ledgr.Domains.VolumeStudio.Spaces.SpaceRental do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.VolumeStudio.Spaces.Space
  alias Ledgr.Domains.VolumeStudio.Spaces.SpaceRentalPayment
  alias Ledgr.Domains.VolumeStudio.PartnerSplits.PartnerSplit
  alias Ledgr.Core.Customers.Customer

  schema "space_rentals" do
    belongs_to :space, Space
    belongs_to :customer, Customer
    belongs_to :partner_split, PartnerSplit
    has_many :payments, SpaceRentalPayment, foreign_key: :space_rental_id

    field :renter_name, :string
    field :renter_phone, :string
    field :renter_email, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :status, :string, default: "confirmed"
    field :amount_cents, :integer
    field :iva_cents, :integer, default: 0
    field :discount_cents, :integer, default: 0
    field :paid_cents, :integer, default: 0
    field :paid_at, :date
    field :notes, :string
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields [:space_id, :renter_name, :amount_cents]
  @optional_fields [:customer_id, :renter_phone, :renter_email, :starts_at, :ends_at,
                    :status, :discount_cents, :paid_at, :notes, :partner_split_id]

  @valid_statuses ~w(confirmed active completed cancelled)

  def changeset(rental, attrs) do
    rental
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_number(:discount_cents, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:space_id)
    |> foreign_key_constraint(:customer_id, on_delete: :nilify_all)
    |> compute_iva()
    |> validate_dates()
  end

  @doc "Changeset used only for recording payments (updates paid_cents and paid_at)."
  def payment_changeset(rental, attrs) do
    rental
    |> cast(attrs, [:paid_cents, :paid_at])
    |> validate_number(:paid_cents, greater_than_or_equal_to: 0)
  end

  @doc "Total amount due: base + IVA − discount, floored at 0."
  def total_cents(%__MODULE__{} = r) do
    max((r.amount_cents || 0) + (r.iva_cents || 0) - (r.discount_cents || 0), 0)
  end

  @doc "Amount still owed."
  def outstanding_cents(%__MODULE__{} = r) do
    max(total_cents(r) - (r.paid_cents || 0), 0)
  end

  @doc "Whether this rental has been fully paid."
  def paid?(%__MODULE__{} = r), do: outstanding_cents(r) == 0

  # ── Private helpers ───────────────────────────────────────

  # IVA is always 16% of the base amount — not user-editable.
  defp compute_iva(changeset) do
    case get_field(changeset, :amount_cents) do
      nil -> changeset
      amount -> put_change(changeset, :iva_cents, round(amount * 0.16))
    end
  end

  # End date must be after start date when both are provided.
  defp validate_dates(changeset) do
    starts = get_field(changeset, :starts_at)
    ends   = get_field(changeset, :ends_at)

    if starts && ends && DateTime.compare(ends, starts) != :gt do
      add_error(changeset, :ends_at, "must be after the start date and time")
    else
      changeset
    end
  end
end
