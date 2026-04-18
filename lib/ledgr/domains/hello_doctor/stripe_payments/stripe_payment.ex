defmodule Ledgr.Domains.HelloDoctor.StripePayments.StripePayment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "stripe_payments" do
    field :stripe_session_id, :string
    field :stripe_payment_intent_id, :string
    field :amount, :float
    field :currency, :string, default: "mxn"
    field :status, :string, default: "paid"
    field :customer_email, :string
    field :customer_name, :string
    field :consultation_id, :string
    field :stripe_fee, :float
    field :product_name, :string
    field :paid_at, :naive_datetime

    timestamps()
  end

  @required ~w[stripe_session_id amount status paid_at]a
  @optional ~w[stripe_payment_intent_id currency customer_email customer_name consultation_id stripe_fee product_name]a

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:stripe_session_id)
  end
end
