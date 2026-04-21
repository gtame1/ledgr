defmodule Ledgr.Domains.AumentaMiPension.OutboundMessages.OutboundMessage do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "outbound_messages" do
    field :phone, :string
    field :message_type, :string
    field :status, :string
    field :sent_at, :naive_datetime
    field :delivered_at, :naive_datetime
    field :read_at, :naive_datetime

    belongs_to :conversation, Ledgr.Domains.AumentaMiPension.Conversations.Conversation
  end
end
