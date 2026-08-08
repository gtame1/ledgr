defmodule Ledgr.Domains.EscuelaDeDinero.Movimientos do
  @moduledoc """
  Reading `movimientos` — the acompañamiento work queue.
  Read-only; the bot owns every row.
  """

  import Ecto.Query

  alias Ledgr.Domains.EscuelaDeDinero.Movimientos.Movimiento
  alias Ledgr.Domains.EscuelaDeDinero.People.Person
  alias Ledgr.Repo

  @doc """
  The queue.

  Default ordering is pendientes first, then oldest due date — an operator
  opening this page should land on the thing that has been waiting longest,
  not on the most recent row.
  """
  def list(opts \\ %{}) do
    from(m in Movimiento,
      join: p in Person,
      on: p.id == m.person_id,
      order_by: [
        asc: fragment("case when ? = 'pendiente' then 0 else 1 end", m.estado),
        asc_nulls_last: m.due_at,
        desc: m.created_at
      ],
      select: %{
        id: m.id,
        person_id: p.id,
        phone: p.phone,
        display_name: p.display_name,
        diagnostico_id: m.diagnostico_id,
        orden: m.orden,
        area: m.area,
        titulo: m.titulo,
        accion_hoy: m.accion_hoy,
        estado: m.estado,
        due_at: m.due_at,
        last_checkin_at: m.last_checkin_at,
        checkin_count: m.checkin_count,
        completed_at: m.completed_at,
        created_at: m.created_at
      }
    )
    |> apply_filters(opts)
    |> Repo.all()
  end

  defp apply_filters(query, opts) do
    now = DateTime.utc_now()

    Enum.reduce(opts, query, fn
      {_k, v}, q when v in [nil, ""] ->
        q

      {:estado, estado}, q ->
        where(q, [m], m.estado == ^estado)

      {:area, area}, q ->
        where(q, [m], m.area == ^area)

      {:vencidos, "1"}, q ->
        where(q, [m], m.estado == "pendiente" and m.due_at < ^now)

      # Three nudges is the sweep's cap, so these will never be touched again
      # without a human. See app/services/checkin.py in the bot.
      {:agotados, "1"}, q ->
        where(q, [m], m.estado == "pendiente" and m.checkin_count >= 3)

      _, q ->
        q
    end)
  end

  @doc "Distinct áreas actually present, for the filter dropdown."
  def areas_present do
    Repo.all(from m in Movimiento, distinct: true, select: m.area, order_by: m.area)
  end
end
