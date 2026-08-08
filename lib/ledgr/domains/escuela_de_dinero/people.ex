defmodule Ledgr.Domains.EscuelaDeDinero.People do
  @moduledoc """
  Reading `people` — the durable unit of this domain.

  Read-only: the bot owns every row here. Nothing in this module writes.
  """

  import Ecto.Query

  alias Ledgr.Domains.EscuelaDeDinero.Conversations.Conversation
  alias Ledgr.Domains.EscuelaDeDinero.Diagnosticos.Diagnostico
  alias Ledgr.Domains.EscuelaDeDinero.KuboReferrals.KuboReferral
  alias Ledgr.Domains.EscuelaDeDinero.Movimientos.Movimiento
  alias Ledgr.Domains.EscuelaDeDinero.People.Person
  alias Ledgr.Repo

  @doc """
  Index rows, each decorated with its latest diagnóstico and last inbound.

  Both joins are LEFT: someone who never got past the consent gate has neither,
  and they're exactly the people worth seeing on this page.
  """
  def list(opts \\ %{}) do
    from(p in Person,
      left_join: d in Diagnostico,
      on: d.id == p.latest_diagnostico_id,
      left_join: c in Conversation,
      on: c.person_id == p.id,
      group_by: [p.id, d.id],
      order_by: [desc: p.created_at],
      select: %{
        id: p.id,
        phone: p.phone,
        display_name: p.display_name,
        etapa: p.etapa,
        mode: p.mode,
        opted_out_at: p.opted_out_at,
        created_at: p.created_at,
        dias_sin_facturar: d.dias_sin_facturar,
        diagnostico_status: d.status,
        last_inbound_at: max(c.last_inbound_at),
        sesiones: count(c.id, :distinct)
      }
    )
    |> apply_filters(opts)
    |> Repo.all()
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {_k, v}, q when v in [nil, ""] ->
        q

      {:etapa, etapa}, q ->
        where(q, [p], p.etapa == ^etapa)

      {:mode, mode}, q ->
        where(q, [p], p.mode == ^mode)

      {:baja, "1"}, q ->
        where(q, [p], not is_nil(p.opted_out_at))

      {:baja, "0"}, q ->
        where(q, [p], is_nil(p.opted_out_at))

      {:search, term}, q ->
        # Phone or display name. Digits-only so "55 1234" matches a stored
        # E.164 number, which is how anyone actually reads a phone off a screen.
        digits = String.replace(term, ~r/\D/, "")
        like = "%#{term}%"

        if digits == "" do
          where(q, [p], ilike(p.display_name, ^like))
        else
          where(
            q,
            [p],
            ilike(p.display_name, ^like) or like(p.phone, ^"%#{digits}%")
          )
        end

      _, q ->
        q
    end)
  end

  @doc "Distinct etapas actually present, for the filter dropdown."
  def etapas_present do
    Repo.all(from p in Person, distinct: true, select: p.etapa, order_by: p.etapa)
  end

  def get!(id), do: Repo.get!(Person, id)

  @doc "Every diagnóstico for a person, newest version first."
  def diagnosticos(person_id) do
    Repo.all(
      from d in Diagnostico,
        where: d.person_id == ^person_id,
        order_by: [desc: d.version]
    )
  end

  @doc "Every movimiento for a person, pendientes first then by due date."
  def movimientos(person_id) do
    Repo.all(
      from m in Movimiento,
        where: m.person_id == ^person_id,
        order_by: [
          asc: fragment("case when ? = 'pendiente' then 0 else 1 end", m.estado),
          asc_nulls_last: m.due_at,
          asc: m.orden
        ]
    )
  end

  @doc "Sessions for a person, newest first, with their message counts."
  def conversations(person_id) do
    Repo.all(
      from c in Conversation,
        left_join: msg in assoc(c, :messages),
        where: c.person_id == ^person_id,
        group_by: c.id,
        order_by: [desc: c.opened_at],
        select: %{
          id: c.id,
          status: c.status,
          initiated_by: c.initiated_by,
          opened_at: c.opened_at,
          last_inbound_at: c.last_inbound_at,
          closed_at: c.closed_at,
          freeform_until: c.freeform_until,
          etapa_at_open: c.etapa_at_open,
          session_summary: c.session_summary,
          message_count: count(msg.id)
        }
    )
  end

  @doc "Affiliate referrals emitted to a person."
  def kubo_referrals(person_id) do
    Repo.all(
      from k in KuboReferral,
        where: k.person_id == ^person_id,
        order_by: [desc: k.sent_at]
    )
  end
end
