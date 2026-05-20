defmodule Ledgr.Domains.AumentaMiPension.CheckupResponses do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.CheckupResponses.CheckupResponse

  def list_responses(opts \\ []) do
    CheckupResponse
    |> maybe_leads_only(opts[:leads_only])
    |> maybe_search(opts[:search])
    |> order_by(desc: :created_at)
    |> limit(^(opts[:limit] || 200))
    |> Repo.all()
  end

  def get_response!(id), do: Repo.get!(CheckupResponse, id)

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
