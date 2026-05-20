defmodule Ledgr.Domains.AumentaMiPension.Payments do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.Payments.Payment

  def list_payments(opts \\ []) do
    Payment
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_product(opts[:product])
    |> order_by(desc: :created_at)
    |> limit(^(opts[:limit] || 200))
    |> Repo.all()
    |> Repo.preload([:customer, :conversation])
  end

  def get_payment!(id) do
    Payment
    |> Repo.get!(id)
    |> Repo.preload([:customer, :conversation])
  end

  def count_paid_in_range(start_date, end_date) do
    Payment
    |> where([p], p.status == "paid")
    |> where(
      [p],
      fragment("?::date", p.paid_at) >= ^start_date and
        fragment("?::date", p.paid_at) <= ^end_date
    )
    |> Repo.aggregate(:count)
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, [p], p.status == ^status)

  defp maybe_filter_product(query, nil), do: query
  defp maybe_filter_product(query, ""), do: query
  defp maybe_filter_product(query, product), do: where(query, [p], p.product == ^product)
end
