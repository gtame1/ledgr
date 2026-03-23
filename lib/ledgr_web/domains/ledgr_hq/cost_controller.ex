defmodule LedgrWeb.Domains.LedgrHQ.CostController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.LedgrHQ.Costs
  alias Ledgr.Domains.LedgrHQ.Costs.Cost
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, _params) do
    costs = Costs.list_costs()
    render(conn, :index, costs: costs)
  end

  def new(conn, _params) do
    changeset = Costs.change_cost(%Cost{})
    render(conn, :new, changeset: changeset, action: dp(conn, "/costs"))
  end

  def create(conn, %{"cost" => params}) do
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:amount_cents])

    case Costs.create_cost(params) do
      {:ok, _cost} ->
        conn
        |> put_flash(:info, "Cost added.")
        |> redirect(to: dp(conn, "/costs"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, action: dp(conn, "/costs"))
    end
  end

  def edit(conn, %{"id" => id}) do
    cost = Costs.get_cost!(id)
    attrs = %{"amount_cents" => MoneyHelper.cents_to_pesos(cost.amount_cents)}
    changeset = Costs.change_cost(cost, attrs)
    render(conn, :edit, cost: cost, changeset: changeset, action: dp(conn, "/costs/#{id}"))
  end

  def update(conn, %{"id" => id, "cost" => params}) do
    cost = Costs.get_cost!(id)
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:amount_cents])

    case Costs.update_cost(cost, params) do
      {:ok, _cost} ->
        conn
        |> put_flash(:info, "Cost updated.")
        |> redirect(to: dp(conn, "/costs"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit, cost: cost, changeset: changeset, action: dp(conn, "/costs/#{id}"))
    end
  end

  def delete(conn, %{"id" => id}) do
    cost = Costs.get_cost!(id)
    {:ok, _} = Costs.delete_cost(cost)

    conn
    |> put_flash(:info, "Cost deleted.")
    |> redirect(to: dp(conn, "/costs"))
  end

  def toggle_active(conn, %{"id" => id}) do
    cost = Costs.get_cost!(id)
    {:ok, _} = Costs.toggle_active(cost)

    conn
    |> put_flash(:info, "Cost #{if cost.active, do: "deactivated", else: "activated"}.")
    |> redirect(to: dp(conn, "/costs"))
  end
end

defmodule LedgrWeb.Domains.LedgrHQ.CostHTML do
  use LedgrWeb, :html

  alias Ledgr.Domains.LedgrHQ.Costs.Cost

  embed_templates "cost_html/*"

  defdelegate category_label(cat), to: Cost
  defdelegate monthly_cents(cost), to: Cost
end
