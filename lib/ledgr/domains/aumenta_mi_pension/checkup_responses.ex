defmodule Ledgr.Domains.AumentaMiPension.CheckupResponses do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.CheckupResponses.CheckupResponse

  def list_responses(opts \\ []) do
    CheckupResponse
    |> maybe_leads_only(opts[:leads_only])
    |> maybe_search(opts[:search])
    # Order by id, not created_at. These rows are immutable lead
    # captures, so id (serial, insertion order) == created_at order but
    # is fully deterministic and immune to the second-precision
    # truncation of `:utc_datetime` (the column holds milliseconds).
    # `neighbors/2` walks the same id ordering.
    |> order_by(desc: :id)
    |> limit(^(opts[:limit] || 200))
    |> Repo.all()
  end

  def get_response!(id), do: Repo.get!(CheckupResponse, id)

  @doc """
  IDs of the checkup responses immediately adjacent to `response` in
  `list_responses/1` ordering (id DESC = newest first), honoring the
  same `:leads_only` / `:search` filters. Mirrors the conversation/lead
  show pages:

    * `:prev_id` — next-**newer** response (higher id, one row up).
    * `:next_id` — next-**older** response (lower id, one row down).

  Navigation spans the full filtered set, ignoring the display `:limit`
  the index applies — so you don't get stuck at row 200.
  """
  def neighbors(%CheckupResponse{id: id}, opts \\ []) do
    base =
      CheckupResponse
      |> maybe_leads_only(opts[:leads_only])
      |> maybe_search(opts[:search])

    prev_id =
      base
      |> where([r], r.id > ^id)
      |> order_by([r], asc: r.id)
      |> limit(1)
      |> select([r], r.id)
      |> Repo.one()

    next_id =
      base
      |> where([r], r.id < ^id)
      |> order_by([r], desc: r.id)
      |> limit(1)
      |> select([r], r.id)
      |> Repo.one()

    %{prev_id: prev_id, next_id: next_id}
  end

  def count(opts \\ []) do
    CheckupResponse
    |> maybe_leads_only(opts[:leads_only])
    |> Repo.aggregate(:count)
  end

  def count_in_range(start_date, end_date) do
    CheckupResponse
    |> where(
      [r],
      fragment("?::date", r.created_at) >= ^start_date and
        fragment("?::date", r.created_at) <= ^end_date
    )
    |> Repo.aggregate(:count)
  end

  defp maybe_leads_only(query, true) do
    where(query, [r], not is_nil(r.contact_phone))
  end

  defp maybe_leads_only(query, _), do: query

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    term = "%#{search}%"

    where(
      query,
      [r],
      ilike(r.contact_name, ^term) or ilike(r.contact_phone, ^term) or
        ilike(r.contact_email, ^term) or ilike(r.contact_nss, ^term) or
        ilike(r.contact_curp, ^term) or ilike(r.utm_campaign, ^term)
    )
  end
end
