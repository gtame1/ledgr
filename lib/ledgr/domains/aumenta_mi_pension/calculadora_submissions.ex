defmodule Ledgr.Domains.AumentaMiPension.CalculadoraSubmissions do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.CalculadoraSubmissions.CalculadoraSubmission

  def list_submissions(opts \\ []) do
    CalculadoraSubmission
    |> maybe_leads_only(opts[:leads_only])
    |> maybe_search(opts[:search])
    |> order_by(desc: :created_at)
    |> limit(^(opts[:limit] || 200))
    |> Repo.all()
  end

  def get_submission!(id), do: Repo.get!(CalculadoraSubmission, id)

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
