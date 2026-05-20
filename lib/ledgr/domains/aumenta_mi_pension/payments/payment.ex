defmodule Ledgr.Domains.AumentaMiPension.Payments.Payment do
  @moduledoc """
  Bot-side payment/order record. Distinct from `StripePayment` — that mirrors
  Stripe's view (one row per Stripe session). This is the bot's source of
  truth, keyed on conversation + product, used to track which conversations
  have paid for which artifact (e.g., consultation, simulation guide).
  """

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "payments" do
    field :product, :string
    field :amount_mxn, :integer
    field :stripe_payment_intent_id, :string
    field :stripe_session_id, :string
    field :status, :string
    field :created_at, :naive_datetime
    field :paid_at, :naive_datetime
    field :refunded_at, :naive_datetime

    belongs_to :conversation, Ledgr.Domains.AumentaMiPension.Conversations.Conversation
    belongs_to :customer, Ledgr.Domains.AumentaMiPension.Customers.Customer
  end
end
