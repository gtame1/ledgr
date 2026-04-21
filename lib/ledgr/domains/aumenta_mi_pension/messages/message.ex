defmodule Ledgr.Domains.AumentaMiPension.Messages.Message do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "messages" do
    field :role, :string
    field :content, :string
    field :message_type, :string
    field :created_at, :naive_datetime

    belongs_to :conversation, Ledgr.Domains.AumentaMiPension.Conversations.Conversation
  end
end
