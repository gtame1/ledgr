defmodule Ledgr.Domains.EscuelaDeDinero.Conversations.Conversation do
  @moduledoc """
  One **session**, not the relationship — a conversation maps to WhatsApp's 24h
  customer-service window. A person accumulates many of these over months.

  Bot-owned (`conversations`) — read-only here.

  `freeform_until` advances on inbound only; business-initiated sessions have it
  NULL (CHECK-enforced), meaning the bot can only reach them with a template.
  """
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "conversations" do
    field :status, :string
    field :initiated_by, :string
    field :opened_at, :utc_datetime
    field :last_inbound_at, :utc_datetime
    field :last_message_at, :utc_datetime
    field :freeform_until, :utc_datetime
    field :closed_at, :utc_datetime
    # Snapshot of Person.etapa when the session opened.
    field :etapa_at_open, :string
    # Written by the memoria sweep, not by the turn pipeline.
    field :session_summary, :string

    belongs_to :person, Ledgr.Domains.EscuelaDeDinero.People.Person
    has_many :messages, Ledgr.Domains.EscuelaDeDinero.Messages.Message
  end
end
