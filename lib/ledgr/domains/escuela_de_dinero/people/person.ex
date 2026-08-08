defmodule Ledgr.Domains.EscuelaDeDinero.People.Person do
  @moduledoc """
  A human, and the durable unit of this domain.

  Bot-owned (`people`) — read-only here. Note that a `Conversation` is a 24h
  WhatsApp session, not the relationship; the relationship is this row.

  `etapa` is monotonic and terminal:
  `nuevo → tc_pendiente → diagnostico_en_curso → diagnostico_listo → acompanamiento`.
  `mode` (`diagnostico` ⇄ `acompanamiento`) is cyclic and orthogonal to it.
  """
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "people" do
    field :phone, :string
    field :display_name, :string
    field :etapa, :string
    field :mode, :string
    field :etapa_regression_reason, :string
    field :terms_accepted, :boolean
    field :terms_accepted_at, :utc_datetime
    field :ai_disclosed_at, :utc_datetime
    # Denormalized pointer, no FK constraint. Deliberately NOT a belongs_to:
    # pairing it with has_many :diagnosticos makes preloads surprising. Join
    # on it explicitly instead.
    field :latest_diagnostico_id, :string
    field :memoria, :string
    field :memoria_updated_at, :utc_datetime
    # Set by the STOP/baja gate. Suppresses every proactive send.
    field :opted_out_at, :utc_datetime
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime

    has_many :conversations, Ledgr.Domains.EscuelaDeDinero.Conversations.Conversation
    has_many :diagnosticos, Ledgr.Domains.EscuelaDeDinero.Diagnosticos.Diagnostico
    has_many :movimientos, Ledgr.Domains.EscuelaDeDinero.Movimientos.Movimiento
  end
end
