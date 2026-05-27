defmodule Ledgr.Domains.AumentaMiPension.Conversations.Conversation do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "conversations" do
    field :status, :string
    field :funnel_stage, :string
    field :consultation_type, :string
    field :stripe_payment_intent_id, :string
    field :recording_consent_accepted_at, :naive_datetime
    field :recording_consent_reply, :string
    field :consent_state, :string
    field :consent_retry_count, :integer
    field :data_review_sent_at, :naive_datetime
    field :created_at, :naive_datetime
    # usec precision: the DB column is timestamp(6). Loading as plain
    # :naive_datetime truncates to seconds, which manufactures
    # same-second ties and breaks `Conversations.neighbors/2` ordering
    # (off-by-one prev/next). Keep full precision so comparisons are exact.
    field :last_message_at, :naive_datetime_usec
    field :escalation_offered_at, :utc_datetime
    field :guide_budget_requested_at, :utc_datetime
    field :guide_delivered_at, :utc_datetime
    field :stall_count, :integer, default: 0
    field :hallucinated_fallback_count, :integer, default: 0

    # Bot's four-axis state model (synced 2026-05-23 after bot migration shipped).
    # The bot is the canonical writer; Ledgr operators override via the
    # `conversation_crm` overlay (CrmEntry has the same field names).
    # Schema management lives on the bot side — these are just mirrors.
    field :qualification_verdict, :string
    field :escalation_status, :string
    field :engagement_health, :string

    belongs_to :customer, Ledgr.Domains.AumentaMiPension.Customers.Customer
    has_many :consultations, Ledgr.Domains.AumentaMiPension.Consultations.Consultation
    has_many :messages, Ledgr.Domains.AumentaMiPension.Messages.Message
    has_one :pension_case, Ledgr.Domains.AumentaMiPension.PensionCases.PensionCase
  end
end
