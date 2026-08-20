defmodule Ledgr.Domains.Viaxe.Bookings.BookingPayment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.Viaxe.Bookings.Booking
  alias Ledgr.Core.Accounting.Account
  alias Ledgr.Core.Partners.Partner

  schema "booking_payments" do
    belongs_to :booking, Booking
    belongs_to :cash_account, Account
    belongs_to :partner, Partner

    field :date, :date
    field :amount_cents, :integer
    field :payment_method, :string
    field :note, :string
    # true  → received BEFORE booking completion (advance commission)
    #         DR Cash / CR Advance Commission (2200)
    # false → received AFTER booking completion (settles receivable)
    #         DR Cash / CR Commission Receivable (1100)
    field :is_advance, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @required_fields [:booking_id, :date, :amount_cents]
  @optional_fields [:payment_method, :cash_account_id, :partner_id, :note, :is_advance]

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_inclusion(:payment_method, ~w(cash transfer card))
    |> foreign_key_constraint(:booking_id)
  end
end
