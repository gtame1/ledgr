defmodule Ledgr.Domains.EscuelaDeDinero.PolicingEvents.PolicingEvent do
  @moduledoc """
  A guardrail-rule violation on one turn. Bot-owned (`policing_events`).

  This is the compliance record, not a debug log. The CRITICAL rules —
  `solicitud_de_credenciales`, `promesa_de_rendimiento`,
  `asesoria_en_inversiones`, `kubo_link_ungated` — map directly onto the brand's
  hard rules and, for the middle two, onto regulated activity in Mexico.

  Also the only reliable source of send failures (`outbound_send_failed`):
  `outbound_messages.status` is never advanced by the bot, so counting failures
  from that column reads 0 forever.
  """
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "policing_events" do
    field :ts, :utc_datetime
    field :conv_id, :string
    field :person_id, :string
    field :turn, :integer
    # The rule name.
    field :event_type, :string
    # INFO | WARNING | CRITICAL
    field :severity, :string
    field :detail, :string
    # First ~200 chars of the reply that tripped the rule.
    field :reply_snippet, :string
    field :rule_version, :string
    # %{"etapa" =>, "mode" =>} or %{"emitter" =>, "message_type" =>}
    field :context, :map
  end
end
