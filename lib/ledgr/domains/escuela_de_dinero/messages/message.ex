defmodule Ledgr.Domains.EscuelaDeDinero.Messages.Message do
  @moduledoc """
  One turn in a session. Bot-owned (`messages`) — read-only here.

  `created_at` is `:utc_datetime_usec` on purpose: two messages in the same
  second are common (the bot sends several in a row), and second precision
  makes transcript ordering non-deterministic.
  """
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "messages" do
    # user | assistant | system
    field :role, :string
    field :content, :string
    # text | audio | image | document | interactive
    field :message_type, :string
    # Inbound Meta id, when known.
    field :wamid, :string
    field :created_at, :utc_datetime_usec

    belongs_to :conversation, Ledgr.Domains.EscuelaDeDinero.Conversations.Conversation
  end
end
