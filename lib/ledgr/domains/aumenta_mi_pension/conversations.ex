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

  @doc """
  Finds the conversations immediately adjacent to `conv` in
  `list_conversations/1` ordering (`last_message_at DESC`, with `id` as
  tiebreaker), honoring the same `:status`, `:funnel_stage`, `:search`
  filter opts. Returns `%{prev_id: id_or_nil, next_id: id_or_nil}` so
  callers can render Prev / Next links without a second round-trip.

  Semantics (Prev = newer, Next = older — i.e. "next" walks **down** the
  newest-first list):
    * `:prev_id` — the conversation with the **next-newer** `last_message_at`.
    * `:next_id` — the conversation with the **next-older** `last_message_at`.

  Conversations with `last_message_at == nil` aren't considered for
  navigation (they have no defined position in the ordering).
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
      |> where(
        [c],
        c.last_message_at > ^lma or
          (c.last_message_at == ^lma and c.id > ^id)
      )
      |> order_by([c], asc: c.last_message_at, asc: c.id)
      |> limit(1)
      |> select([c], c.id)
      |> Repo.one()

    next_id =
      base
      |> where(
        [c],
        c.last_message_at < ^lma or
          (c.last_message_at == ^lma and c.id < ^id)
      )
      |> order_by([c], desc: c.last_message_at, desc: c.id)
      |> limit(1)
      |> select([c], c.id)
      |> Repo.one()

    %{prev_id: prev_id, next_id: next_id}
  end

  @doc """
  Funnel stages the bot writes to `conversations.funnel_stage`.

  The column is mid-migration (2026-05-23) from a flat legacy vocabulary
  to the four-axis state model. Both vocabularies coexist on rows until
  the bot finishes its backfill, so this list is the **union** of:

    * Legacy values (greeting, education, ..., completed) — still on
      most rows.
    * New four-axis funnel_stage values (intake, qualifying, terminal,
      escalating, closed) — what the bot is writing on new conversations.

  Source of truth lives in the bot's state machine; this list is a
  defensive mirror — keep it in sync. The `FunnelStageAudit` worker
  surfaces drift on boot.
  """
  def funnel_stages do
    ~w[
      intake
      qualifying
      terminal
      escalating
      closed
      greeting
      education
      data_collection
      qualification
      simulation_sent
      agent_offered
      agent_search
      agent_recommended
      consultation_active
      consultation_complete
      guide_offered
      guide_delivered
      guide_paid
      payment_link_sent
      completed
    ]
  end

  def statuses, do: ~w[active closed]

  @doc """
  Audits the in-code `funnel_stages/0` allow-list against
  `SELECT DISTINCT funnel_stage FROM conversations`. Returns:

    * `:unknown_in_db` — stages present on rows but NOT in our enum.
      These mean the bot has started writing a value we don't render
      properly in dropdowns/labels. Fix by updating `funnel_stages/0`
      and the label map in `ConversationListHTML`.

    * `:missing_in_db` — stages in our enum that no row currently uses.
      Informational; may be legitimately rare or fully deprecated.

    * `:matched` — stages in both.

  Cheap (one column, one DISTINCT) but does hit the DB — call from a
  boot worker or iex on demand, not on every request.
  """
  def audit_funnel_stages do
    db_stages =
      from(c in Conversation,
        where: not is_nil(c.funnel_stage),
        distinct: true,
        select: c.funnel_stage
      )
      |> Repo.all()
      |> MapSet.new()

    code_stages = MapSet.new(funnel_stages())

    %{
      unknown_in_db: db_stages |> MapSet.difference(code_stages) |> Enum.sort(),
      missing_in_db: code_stages |> MapSet.difference(db_stages) |> Enum.sort(),
      matched: db_stages |> MapSet.intersection(code_stages) |> Enum.sort()
    }
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
      join: cu in assoc(c, :customer),
      where: ilike(cu.full_name, ^term) or ilike(cu.display_name, ^term) or ilike(cu.phone, ^term)
    )
  end
end
