defmodule Ledgr.Domains.HelloDoctor.Conversations do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Conversations.Conversation

  def list_conversations(opts \\ []) do
    Conversation
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_funnel(opts[:funnel_stage])
    |> maybe_search(opts[:search])
    |> order_by(desc: :last_message_at)
    |> Repo.all()
    |> Repo.preload([:patient, :consultations])
  end

  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload([:patient, :consultations, :messages, :medical_record])
  end

  @doc """
  Finds the conversations immediately adjacent to `conv` in
  `list_conversations/1` ordering (`last_message_at DESC`, `id` as
  tiebreaker), honoring the same `:status`, `:funnel_stage`, `:search`
  filter opts. Returns `%{prev_id: id_or_nil, next_id: id_or_nil}` so the
  show page can render Prev / Next without a second list round-trip.

  Prev = newer, Next = older — "next" walks down the newest-first list.
  Conversations with `last_message_at == nil` have no position in the
  ordering and aren't navigable.
  """
  def neighbors(conv, opts \\ [])

  def neighbors(%Conversation{last_message_at: nil}, _opts) do
    %{prev_id: nil, next_id: nil}
  end

  def neighbors(%Conversation{id: id, last_message_at: lma}, opts) do
    base =
      Conversation
      |> maybe_filter_status(opts[:status])
      |> maybe_filter_funnel(opts[:funnel_stage])
      |> maybe_search(opts[:search])
      |> where([c], c.id != ^id and not is_nil(c.last_message_at))

    prev_id =
      base
      |> where([c], c.last_message_at > ^lma or (c.last_message_at == ^lma and c.id > ^id))
      |> order_by([c], asc: c.last_message_at, asc: c.id)
      |> limit(1)
      |> select([c], c.id)
      |> Repo.one()

    next_id =
      base
      |> where([c], c.last_message_at < ^lma or (c.last_message_at == ^lma and c.id < ^id))
      |> order_by([c], desc: c.last_message_at, desc: c.id)
      |> limit(1)
      |> select([c], c.id)
      |> Repo.one()

    %{prev_id: prev_id, next_id: next_id}
  end

  def funnel_stages do
    ~w[triage doctor_recommended doctor_assigned consultation_active completed]
  end

  def statuses do
    ~w[active closed]
  end

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
      join: p in assoc(c, :patient),
      where: ilike(p.full_name, ^term) or ilike(p.display_name, ^term) or ilike(p.phone, ^term)
    )
  end
end
