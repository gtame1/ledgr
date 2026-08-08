defmodule Ledgr.Domains.EscuelaDeDinero.Conversations do
  @moduledoc """
  Reading `conversations` and their `messages`.

  A conversation is one 24h WhatsApp session, not the relationship — a person
  accumulates many over months. Read-only; the bot owns every row.
  """

  import Ecto.Query

  alias Ledgr.Domains.EscuelaDeDinero.Conversations.Conversation
  alias Ledgr.Domains.EscuelaDeDinero.Messages.Message
  alias Ledgr.Domains.EscuelaDeDinero.People.Person
  alias Ledgr.Domains.EscuelaDeDinero.PolicingEvents.PolicingEvent
  alias Ledgr.Repo

  def list(opts \\ %{}) do
    from(c in Conversation,
      join: p in Person,
      on: p.id == c.person_id,
      left_join: m in Message,
      on: m.conversation_id == c.id,
      group_by: [c.id, p.id],
      order_by: [desc: c.opened_at],
      select: %{
        id: c.id,
        person_id: p.id,
        phone: p.phone,
        display_name: p.display_name,
        status: c.status,
        initiated_by: c.initiated_by,
        opened_at: c.opened_at,
        last_inbound_at: c.last_inbound_at,
        closed_at: c.closed_at,
        freeform_until: c.freeform_until,
        etapa_at_open: c.etapa_at_open,
        session_summary: c.session_summary,
        message_count: count(m.id)
      }
    )
    |> apply_filters(opts)
    |> Repo.all()
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {_k, v}, q when v in [nil, ""] -> q
      {:status, status}, q -> where(q, [c], c.status == ^status)
      {:initiated_by, by}, q -> where(q, [c], c.initiated_by == ^by)
      {:person_id, id}, q -> where(q, [c], c.person_id == ^id)
      _, q -> q
    end)
  end

  def get!(id) do
    Repo.one!(
      from c in Conversation,
        join: p in Person,
        on: p.id == c.person_id,
        where: c.id == ^id,
        select: %{
          id: c.id,
          person_id: p.id,
          phone: p.phone,
          display_name: p.display_name,
          etapa: p.etapa,
          status: c.status,
          initiated_by: c.initiated_by,
          opened_at: c.opened_at,
          last_inbound_at: c.last_inbound_at,
          last_message_at: c.last_message_at,
          freeform_until: c.freeform_until,
          closed_at: c.closed_at,
          etapa_at_open: c.etapa_at_open,
          session_summary: c.session_summary
        }
    )
  end

  @doc """
  The transcript, oldest first.

  Ordered in SQL rather than in Elixir — `created_at` is a `DateTime`, and
  `Enum.sort_by/3` with the wrong module raises on it.
  """
  def messages(conversation_id) do
    Repo.all(
      from m in Message,
        where: m.conversation_id == ^conversation_id,
        order_by: [asc: m.created_at]
    )
  end

  @doc """
  Guardrail violations recorded during this session, keyed by turn so the
  transcript can flag them in place. Events with no turn land under `nil`.
  """
  def policing_by_turn(conversation_id) do
    Repo.all(from e in PolicingEvent, where: e.conv_id == ^conversation_id, order_by: e.ts)
    |> Enum.group_by(& &1.turn)
  end
end
