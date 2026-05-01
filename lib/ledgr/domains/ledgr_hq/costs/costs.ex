defmodule Ledgr.Domains.LedgrHQ.Costs do
  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.LedgrHQ.Costs.Cost

  def list_costs(opts \\ []) do
    active_only = Keyword.get(opts, :active_only, false)

    Cost
    |> maybe_active_only(active_only)
    |> order_by([c], asc: c.category, asc: c.name)
    |> Repo.all()
  end

  defp maybe_active_only(query, false), do: query
  defp maybe_active_only(query, true), do: where(query, active: true)

  def get_cost!(id), do: Repo.get!(Cost, id)

  def change_cost(%Cost{} = cost, attrs \\ %{}) do
    Cost.changeset(cost, attrs)
  end

  def create_cost(attrs \\ %{}) do
    %Cost{}
    |> Cost.changeset(attrs)
    |> Repo.insert()
  end

  def update_cost(%Cost{} = cost, attrs) do
    cost
    |> Cost.changeset(attrs)
    |> Repo.update()
  end

  def delete_cost(%Cost{} = cost) do
    Repo.delete(cost)
  end

  def toggle_active(%Cost{} = cost) do
    cost
    |> Ecto.Changeset.change(active: !cost.active)
    |> Repo.update()
  end

  @doc "Returns total normalized monthly cost in cents across all active costs."
  def total_monthly_cents do
    list_costs(active_only: true)
    |> Enum.reduce(0, fn cost, acc -> acc + Cost.monthly_cents(cost) end)
  end
end
