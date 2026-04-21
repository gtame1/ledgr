defmodule Ledgr.Domains.AumentaMiPension.Conversations do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.Conversations.Conversation

  def list_conversations(opts \\ []) do
    Conversation
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_funnel(opts[:funnel_stage])
    |> maybe_search(opts[:search])
    |> order_by(desc: :last_message_at)
    |> Repo.all()
    |> Repo.preload([:customer, :consultations])
  end

  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload([:customer, :consultations, :messages, :pension_case])
  end

  def funnel_stages do
    ~w[greeting data_collection qualification simulation_sent agent_recommended consultation_active completed]
  end

  def statuses, do: ~w[active closed]

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, [c], c.status == ^status)

  defp maybe_filter_funnel(query, nil), do: query
  defp maybe_filter_funnel(query, ""), do: query
  defp maybe_filter_funnel(query, stage), do: where(query, [c], c.funnel_stage == ^stage)

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query
  defp maybe_search(query, search) do
    term = "%#{search}%"
    from(c in query,
      join: cu in assoc(c, :customer),
      where: ilike(cu.full_name, ^term) or ilike(cu.display_name, ^term) or ilike(cu.phone, ^term)
    )
  end
end
