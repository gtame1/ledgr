defmodule Ledgr.Domains.EscuelaDeDinero.Diagnosticos do
  @moduledoc """
  Reading `diagnosticos`. Read-only; the bot owns every row.
  """

  import Ecto.Query

  alias Ledgr.Domains.EscuelaDeDinero.Diagnosticos.Diagnostico
  alias Ledgr.Domains.EscuelaDeDinero.Movimientos.Movimiento
  alias Ledgr.Domains.EscuelaDeDinero.People.Person
  alias Ledgr.Repo

  def list(opts \\ %{}) do
    from(d in Diagnostico,
      join: p in Person,
      on: p.id == d.person_id,
      order_by: [desc: d.started_at],
      select: %{
        id: d.id,
        person_id: p.id,
        phone: p.phone,
        display_name: p.display_name,
        version: d.version,
        status: d.status,
        started_at: d.started_at,
        playback_sent_at: d.playback_sent_at,
        confirmed_at: d.confirmed_at,
        completed_at: d.completed_at,
        dias_sin_facturar: d.dias_sin_facturar,
        areas: d.areas
      }
    )
    |> apply_filters(opts)
    |> Repo.all()
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {_k, v}, q when v in [nil, ""] ->
        q

      {:status, status}, q ->
        where(q, [d], d.status == ^status)

      {:colchon, estado}, q ->
        where(q, [d], fragment("(? -> 'colchon' ->> 'estado')", d.areas) == ^estado)

      {:banda, banda}, q ->
        apply_banda(q, banda)

      _, q ->
        q
    end)
  end

  # Bands mirror the bot's own colchón thresholds (30 / 90), plus a
  # "less than a week" band. See StateLabels.Helpers.dias_band/1.
  defp apply_banda(q, "critico"), do: where(q, [d], d.dias_sin_facturar < 7)

  defp apply_banda(q, "corto"),
    do: where(q, [d], d.dias_sin_facturar >= 7 and d.dias_sin_facturar < 30)

  defp apply_banda(q, "medio"),
    do: where(q, [d], d.dias_sin_facturar >= 30 and d.dias_sin_facturar < 90)

  defp apply_banda(q, "largo"), do: where(q, [d], d.dias_sin_facturar >= 90)
  defp apply_banda(q, _), do: q

  def get!(id) do
    Repo.one!(
      from d in Diagnostico,
        join: p in Person,
        on: p.id == d.person_id,
        where: d.id == ^id,
        select: %{
          id: d.id,
          person_id: p.id,
          phone: p.phone,
          display_name: p.display_name,
          etapa: p.etapa,
          version: d.version,
          status: d.status,
          schema_version: d.schema_version,
          started_at: d.started_at,
          playback_sent_at: d.playback_sent_at,
          confirmed_at: d.confirmed_at,
          completed_at: d.completed_at,
          started_in_conversation_id: d.started_in_conversation_id,
          dias_sin_facturar: d.dias_sin_facturar,
          headline: d.headline,
          respuestas: d.respuestas,
          areas: d.areas,
          movimientos_snapshot: d.movimientos
        }
    )
  end

  @doc """
  The live movimiento rows for a diagnóstico.

  Distinct from the `movimientos` JSONB column on the diagnóstico itself, which
  is an immutable snapshot of what was authored. These are the trackable rows.
  """
  def movimientos(diagnostico_id) do
    Repo.all(
      from m in Movimiento,
        where: m.diagnostico_id == ^diagnostico_id,
        order_by: [asc: m.orden]
    )
  end
end
