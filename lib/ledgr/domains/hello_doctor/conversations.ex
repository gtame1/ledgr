defmodule Ledgr.Domains.HelloDoctor.Conversations do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Conversations.Conversation

  def list_conversations(opts \\ []) do
    Conversation
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_funnel(opts[:funnel_stage])
    |> maybe_search(opts[:search])
    |> maybe_filter_date_range(opts[:start_date], opts[:end_date])
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
      |> maybe_filter_date_range(opts[:start_date], opts[:end_date])
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

  # Filters `created_at` to a Mexico-City calendar range. Accepts ISO date
  # strings ("2026-06-01") or `Date`s; blank/invalid bounds are ignored.
  # Half-open `>= start 00:00 MX` / `< end+1 00:00 MX` — UTC-correct against
  # the naive `created_at` column (see HelloDoctor.mx_day_start_utc_naive/1).
  defp maybe_filter_date_range(query, start_date, end_date) do
    query
    |> maybe_filter_start(parse_date(start_date))
    |> maybe_filter_end(parse_date(end_date))
  end

  defp maybe_filter_start(query, nil), do: query

  defp maybe_filter_start(query, %Date{} = d) do
    bound = Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive(d)
    where(query, [c], c.created_at >= ^bound)
  end

  defp maybe_filter_end(query, nil), do: query

  defp maybe_filter_end(query, %Date{} = d) do
    bound = Ledgr.Domains.HelloDoctor.mx_day_end_utc_naive(d)
    where(query, [c], c.created_at < ^bound)
  end

  defp parse_date(%Date{} = d), do: d

  defp parse_date(str) when is_binary(str) and str != "" do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_date(_), do: nil
end
