defmodule Ledgr.Domains.EscuelaDeDinero.OutboundMessages.OutboundMessage do
  @moduledoc """
  One row per message the bot sent, keyed by the wamid Meta returns.
  Bot-owned (`outbound_messages`) — read-only here.

  Keyed by phone rather than person_id because a send can precede person
  resolution.

  ⚠️ `status`, `delivered_at` and `read_at` are **never advanced** — the Meta
  `statuses` webhook branch only logs. Do not build a delivery rate or a
  "fallidos" count off them; use `policing_events.event_type =
  'outbound_send_failed'` instead. `emitter` and `sent_at` are trustworthy.
  """
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "outbound_messages" do
    field :phone, :string
    # text | media | interactive | template
    field :message_type, :string
    # sent | delivered | read | failed — see the warning above.
    field :status, :string
    field :conversation_id, :string
    # pipeline | confirmar | checkin | kubo | first_contact | alerts.
    # Load-bearing for the `kubo_link_ungated` rule: an affiliate URL is only
    # legitimate when emitter == "kubo".
    field :emitter, :string
    field :sent_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :read_at, :utc_datetime
    field :error_detail, :string
  end
end
