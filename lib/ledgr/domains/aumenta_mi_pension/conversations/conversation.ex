defmodule Ledgr.Domains.AumentaMiPension.Conversations.Conversation do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "conversations" do
    field :status, :string
    field :funnel_stage, :string
    field :qualifies, :boolean
    field :recommended_modalidad, :string
    field :resolved_without_agent, :boolean
    field :agent_recommended, :boolean
    field :agent_declined_by_customer, :boolean
    field :consultation_type, :string
    field :stripe_payment_intent_id, :string
    field :recording_consent_accepted_at, :naive_datetime
    field :recording_consent_reply, :string
    field :consent_state, :string
    field :consent_retry_count, :integer
    field :data_review_sent_at, :naive_datetime
    field :created_at, :naive_datetime
    field :last_message_at, :naive_datetime

    belongs_to :customer, Ledgr.Domains.AumentaMiPension.Customers.Customer
    has_many :consultations, Ledgr.Domains.AumentaMiPension.Consultations.Consultation
    has_many :messages, Ledgr.Domains.AumentaMiPension.Messages.Message
    has_one :pension_case, Ledgr.Domains.AumentaMiPension.PensionCases.PensionCase
  end
end
