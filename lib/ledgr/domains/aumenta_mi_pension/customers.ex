defmodule Ledgr.Domains.AumentaMiPension.Customers do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.Customers.Customer

  def list_customers(opts \\ []) do
    Customer
    |> maybe_search(opts[:search])
    |> order_by(desc: :created_at)
    |> Repo.all()
  end

  def get_customer!(id) do
    Customer
    |> Repo.get!(id)
    |> Repo.preload([consultations: [:agent], pension_cases: []])
  end

  def count_new(start_date, end_date) do
    Customer
    |> where([c], fragment("?::date", c.created_at) >= ^start_date and fragment("?::date", c.created_at) <= ^end_date)
    |> Repo.aggregate(:count)
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query
  defp maybe_search(query, search) do
    term = "%#{search}%"
    where(query, [c], ilike(c.full_name, ^term) or ilike(c.display_name, ^term) or ilike(c.phone, ^term) or ilike(c.curp, ^term) or ilike(c.nss, ^term))
  end
end
