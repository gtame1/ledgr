defmodule Ledgr.Domains.EscuelaDeDinero.Diagnosticos.Diagnostico do
  @moduledoc """
  The product artifact, versioned per person. Bot-owned (`diagnosticos`).

  The lifecycle worth measuring is
  `started_at → playback_sent_at → confirmed_at → completed_at`:
  the bot plays the six captured answers back, the person confirms, and only
  then is the entrega computed. Most drop-off happens between those stamps.

  `dias_sin_facturar = floor(guardado_disponible / (gasto_fijo_mensual / 30))`
  — the headline number the whole product exists to produce.

  ## Note on `status = "abandoned"`

  The value is in the CHECK constraint and `abandoned_at` exists, but nothing in
  the bot writes either today. Don't render a bucket for it — a permanent zero
  reads as "nobody abandons", which is the opposite of the truth.
  """
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "diagnosticos" do
    field :person_id, :string
    field :started_in_conversation_id, :string
    field :version, :integer
    # in_progress | complete | abandoned
    field :status, :string
    field :schema_version, :string
    field :started_at, :utc_datetime
    field :confirmed_at, :utc_datetime
    field :playback_sent_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :abandoned_at, :utc_datetime
    field :dias_sin_facturar, :integer

    # JSONB. `headline` = %{"dias_sin_facturar" => n, "texto" => "..."}.
    field :headline, :map
    # The six captured slots (+ optional colour) — see EscuelaDeDinero.Diagnosticos.
    field :respuestas, :map
    # %{"colchon" => %{"estado" =>, "dias" =>}, "retiro" => %{"estado" =>}, ...}
    field :areas, :map
    # Immutable snapshot of the three movimientos as authored. The live,
    # trackable rows are in the `movimientos` TABLE — see :movimiento_rows below.
    field :movimientos, {:array, :map}

    belongs_to :person, Ledgr.Domains.EscuelaDeDinero.People.Person, define_field: false

    # Named :movimiento_rows, NOT :movimientos — the JSONB field above already
    # owns that name and Ecto raises on the collision.
    has_many :movimiento_rows, Ledgr.Domains.EscuelaDeDinero.Movimientos.Movimiento
  end
end
