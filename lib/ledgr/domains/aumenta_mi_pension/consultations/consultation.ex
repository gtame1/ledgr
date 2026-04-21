defmodule Ledgr.Domains.AumentaMiPension.Consultations.Consultation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @timestamps_opts [type: :naive_datetime]

  schema "consultations" do
    field :status, :string
    field :consultation_type, :string, default: "messaging"
    field :assigned_at, :naive_datetime
    field :accepted_at, :naive_datetime
    field :completed_at, :naive_datetime
    field :duration_minutes, :integer
    field :agent_notes, :string
    field :inactivity_ping_sent_at, :naive_datetime
    field :payment_status, :string
    field :payment_amount, :float
    field :payment_confirmed_at, :naive_datetime
    field :stripe_payment_intent_id, :string
    field :last_broadcast_at, :naive_datetime
    field :rejected_by_agents, :string
    field :awaiting_extension_response, :boolean, default: false
    field :search_extended_count, :integer, default: 0
    field :audit_json, :string
    field :customer_summary, :string
    field :customer_rating, :integer
    field :customer_platform_rating, :integer
    field :customer_comment, :string
    field :agent_rating, :integer
    field :agent_platform_rating, :integer
    field :agent_comment, :string
    field :review_started_at, :naive_datetime

    belongs_to :customer, Ledgr.Domains.AumentaMiPension.Customers.Customer
    belongs_to :agent, Ledgr.Domains.AumentaMiPension.Agents.Agent
    belongs_to :conversation, Ledgr.Domains.AumentaMiPension.Conversations.Conversation
    has_many :calls, Ledgr.Domains.AumentaMiPension.ConsultationCalls.ConsultationCall

    # No inserted_at/updated_at — bot uses assigned_at as creation timestamp
  end

  @statuses ~w[pending assigned active completed cancelled]
  @payment_statuses ~w[pending paid confirmed failed refunded]

  @required ~w[id conversation_id customer_id status payment_status assigned_at]a
  @optional ~w[agent_id consultation_type accepted_at completed_at duration_minutes agent_notes inactivity_ping_sent_at payment_amount payment_confirmed_at stripe_payment_intent_id last_broadcast_at rejected_by_agents awaiting_extension_response search_extended_count audit_json customer_summary customer_rating customer_platform_rating customer_comment agent_rating agent_platform_rating agent_comment review_started_at]a

  def changeset(consultation, attrs) do
    consultation
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:conversation_id)
  end

  def statuses, do: @statuses
  def payment_statuses, do: @payment_statuses
end
