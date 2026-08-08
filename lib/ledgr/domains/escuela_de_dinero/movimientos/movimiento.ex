defmodule Ledgr.Domains.EscuelaDeDinero.Movimientos.Movimiento do
  @moduledoc """
  One of the three moves handed to a person at entrega, tracked live through
  acompañamiento. Bot-owned (`movimientos`) — read-only here.

  `movimiento` 1 is always something they can do today. `checkin_count` is
  capped at 3 by the sweep, so a row sitting at 3 and still `pendiente` will
  never be nudged again — that's the queue worth surfacing to an operator.
  """
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "movimientos" do
    field :diagnostico_id, :string
    field :person_id, :string
    # 1 | 2 | 3
    field :orden, :integer
    # colchon | estructura_fiscal | retiro | seguros | deuda
    field :area, :string
    field :titulo, :string
    field :accion_hoy, :string
    # pendiente | en_proceso | hecho | descartado
    field :estado, :string
    field :due_at, :utc_datetime
    field :last_checkin_at, :utc_datetime
    field :checkin_count, :integer
    field :completed_at, :utc_datetime
    field :created_at, :utc_datetime

    belongs_to :person, Ledgr.Domains.EscuelaDeDinero.People.Person, define_field: false

    belongs_to :diagnostico, Ledgr.Domains.EscuelaDeDinero.Diagnosticos.Diagnostico,
      define_field: false
  end
end
