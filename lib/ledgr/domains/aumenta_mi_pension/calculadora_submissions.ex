defmodule Ledgr.Domains.AumentaMiPension.CalculadoraSubmissions do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.CalculadoraSubmissions.CalculadoraSubmission

  def list_submissions(opts \\ []) do
    CalculadoraSubmission
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

  def get_submission!(id), do: Repo.get!(CalculadoraSubmission, id)

  @doc """
  IDs of the calculadora submissions immediately adjacent to
  `submission` in `list_submissions/1` ordering (id DESC = newest
  first), honoring the same `:leads_only` / `:search` filters.

    * `:prev_id` — next-**newer** submission (higher id, one row up).
    * `:next_id` — next-**older** submission (lower id, one row down).

  Navigation spans the full filtered set, ignoring the display `:limit`.
  """
  def neighbors(%CalculadoraSubmission{id: id}, opts \\ []) do
    base =
      CalculadoraSubmission
      |> maybe_leads_only(opts[:leads_only])
      |> maybe_search(opts[:search])

    prev_id =
      base
      |> where([s], s.id > ^id)
      |> order_by([s], asc: s.id)
      |> limit(1)
      |> select([s], s.id)
      |> Repo.one()

    next_id =
      base
      |> where([s], s.id < ^id)
      |> order_by([s], desc: s.id)
      |> limit(1)
      |> select([s], s.id)
      |> Repo.one()

    %{prev_id: prev_id, next_id: next_id}
  end

  def count(opts \\ []) do
    CalculadoraSubmission
    |> maybe_leads_only(opts[:leads_only])
    |> Repo.aggregate(:count)
  end

  def count_in_range(start_date, end_date) do
    CalculadoraSubmission
    |> where(
      [s],
      fragment("?::date", s.created_at) >= ^start_date and
        fragment("?::date", s.created_at) <= ^end_date
    )
    |> Repo.aggregate(:count)
  end

  defp maybe_leads_only(query, true) do
    where(query, [s], not is_nil(s.contact_phone))
  end

  defp maybe_leads_only(query, _), do: query

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    term = "%#{search}%"

    where(
      query,
      [s],
      ilike(s.contact_name, ^term) or ilike(s.contact_phone, ^term) or
        ilike(s.contact_email, ^term) or ilike(s.utm_campaign, ^term)
    )
  end
end
