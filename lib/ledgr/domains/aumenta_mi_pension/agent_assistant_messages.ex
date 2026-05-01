defmodule Ledgr.Domains.AumentaMiPension.AgentAssistantMessages do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.AgentAssistantMessages.AgentAssistantMessage
  alias Ledgr.Domains.AumentaMiPension.Agents.Agent

  @doc "Returns one summary row per agent: agent info, message count, last message time."
  def list_by_agent(opts \\ []) do
    search = opts[:search]

    query =
      from a in Agent,
        join: m in AgentAssistantMessage,
        on: m.agent_id == a.id,
        group_by: a.id,
        select: %{
          agent_id: a.id,
          agent_name: a.name,
          agent_available: a.is_available,
          message_count: count(m.id),
          last_message_at: max(m.created_at)
        },
        order_by: [desc: max(m.created_at)]

    query =
      if search && search != "" do
        term = "%#{search}%"
        where(query, [a, _m], ilike(a.name, ^term))
      else
        query
      end

    Repo.all(query)
  end

  def list_for_agent(agent_id, opts \\ []) do
    consultation_id = opts[:consultation_id]

    query =
      AgentAssistantMessage
      |> where([m], m.agent_id == ^agent_id)
      |> order_by([m], asc: m.created_at)

    query =
      if consultation_id do
        where(query, [m], m.consultation_id == ^consultation_id)
      else
        query
      end

    Repo.all(query)
  end

  def get_agent_thread!(agent_id) do
    agent = Repo.get!(Agent, agent_id)

    messages =
      AgentAssistantMessage
      |> where([m], m.agent_id == ^agent_id)
      |> order_by([m], asc: m.created_at)
      |> Repo.all()

    {agent, messages}
  end

  def consultation_ids_for_agent(agent_id) do
    AgentAssistantMessage
    |> where([m], m.agent_id == ^agent_id and not is_nil(m.consultation_id))
    |> select([m], m.consultation_id)
    |> distinct(true)
    |> Repo.all()
  end
end
