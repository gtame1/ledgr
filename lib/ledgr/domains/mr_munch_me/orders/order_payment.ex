defmodule Ledgr.Domains.MrMunchMe.Orders.OrderPayment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.MrMunchMe.Orders.Order
  alias Ledgr.Core.Accounting.Account
  alias Ledgr.Core.Partners.Partner

  schema "order_payments" do
    field :payment_date, :date
    field :amount_cents, :integer
    field :method, :string
    field :note, :string
    field :is_deposit, :boolean, default: false

    # Split payment fields
    field :customer_amount_cents, :integer
    field :partner_amount_cents, :integer

    belongs_to :order, Order
    belongs_to :paid_to_account, Account
    belongs_to :partner, Partner
    belongs_to :partner_payable_account, Account, foreign_key: :partner_payable_account_id

    timestamps()
  end

  @required ~w(order_id payment_date amount_cents paid_to_account_id)a
  @optional ~w(method note is_deposit customer_amount_cents partner_amount_cents partner_id partner_payable_account_id)a

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_number(:customer_amount_cents, greater_than_or_equal_to: 0)
    |> validate_number(:partner_amount_cents, greater_than_or_equal_to: 0)
    |> validate_split_payment()
    |> assoc_constraint(:order)
    |> assoc_constraint(:paid_to_account)
    |> assoc_constraint(:partner)
    |> assoc_constraint(:partner_payable_account)
  end

  # Validate split payment: if partner_amount is set, partner and partner_payable_account must be set
  # Customer amount + partner amount must equal total amount
  defp validate_split_payment(changeset) do
    amount_cents = get_field(changeset, :amount_cents)
    customer_amount_cents = get_field(changeset, :customer_amount_cents)
    partner_amount_cents = get_field(changeset, :partner_amount_cents)
    partner_id = get_field(changeset, :partner_id)

    # Determine if this is a split payment
    # It's a split payment if partner_amount_cents is explicitly set and > 0
    # OR if partner_id is set (indicating split payment intent)
    is_split_payment =
      (partner_amount_cents && partner_amount_cents > 0) || (partner_id && partner_id != "")

    if is_split_payment do
      # This is a split payment - validate split payment requirements
      customer_amount_cents = customer_amount_cents || amount_cents
      partner_amount_cents = partner_amount_cents || 0

      changeset
      |> validate_required([:partner_id, :partner_payable_account_id])
      |> validate_split_amounts(customer_amount_cents, partner_amount_cents, amount_cents)
    else
      # Not a split payment - clear split payment fields and set customer_amount to total
      changeset
      |> put_change(:customer_amount_cents, nil)
      |> put_change(:partner_amount_cents, nil)
      |> put_change(:partner_id, nil)
      |> put_change(:partner_payable_account_id, nil)
    end
  end

  defp validate_split_amounts(changeset, customer_amount, partner_amount, total_amount) do
    calculated_total = (customer_amount || 0) + (partner_amount || 0)

    if calculated_total != total_amount do
      add_error(
        changeset,
        :base,
        "Customer amount (#{customer_amount || 0}) + Partner amount (#{partner_amount || 0}) must equal total amount (#{total_amount})"
      )
    else
      changeset
    end
  end
end
