defmodule Ledgr.Domains.AumentaMiPension.Agents do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.Agents.Agent

  def list_agents(opts \\ []) do
    Agent
    |> maybe_filter_available(opts[:status])
    |> maybe_search(opts[:search])
    |> order_by(:name)
    |> Repo.all()
  end

  def get_agent!(id) do
    Agent
    |> Repo.get!(id)
    |> Repo.preload(consultations: :customer)
  end

  def create_agent(attrs) do
    %Agent{}
    |> Agent.changeset(Map.put_new(attrs, "id", Ecto.UUID.generate()))
    |> Repo.insert()
  end

  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
  end

  def delete_agent(%Agent{} = agent), do: Repo.delete(agent)

  def change_agent(%Agent{} = agent, attrs \\ %{}), do: Agent.changeset(agent, attrs)

  def toggle_availability(%Agent{} = agent) do
    update_agent(agent, %{is_available: !agent.is_available})
  end

  def count_by_status(:active), do: Agent |> where([a], a.is_available == true) |> Repo.aggregate(:count)
  def count_by_status(:inactive), do: Agent |> where([a], a.is_available == false) |> Repo.aggregate(:count)
  def count_by_status(_), do: Repo.aggregate(Agent, :count)

  def count_all, do: Repo.aggregate(Agent, :count)

  def agent_options do
    Agent
    |> where([a], a.is_available == true)
    |> order_by(:name)
    |> Repo.all()
    |> Enum.map(&{&1.name, &1.id})
  end

  defp maybe_filter_available(query, nil), do: query
  defp maybe_filter_available(query, ""), do: query
  defp maybe_filter_available(query, "active"), do: where(query, [a], a.is_available == true)
  defp maybe_filter_available(query, "inactive"), do: where(query, [a], a.is_available == false)
  defp maybe_filter_available(query, _), do: query

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query
  defp maybe_search(query, search) do
    term = "%#{search}%"
    where(query, [a], ilike(a.name, ^term) or ilike(a.phone, ^term) or ilike(a.email, ^term))
  end
end
