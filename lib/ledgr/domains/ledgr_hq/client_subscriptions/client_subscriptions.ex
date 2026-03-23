defmodule Ledgr.Domains.LedgrHQ.ClientSubscriptions do
  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.LedgrHQ.ClientSubscriptions.ClientSubscription

  def list_client_subscriptions(opts \\ []) do
    status = Keyword.get(opts, :status)

    ClientSubscription
    |> maybe_filter_status(status)
    |> preload([:client, :subscription_plan])
    |> order_by([cs], desc: cs.inserted_at)
    |> Repo.all()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  def get_client_subscription!(id) do
    ClientSubscription
    |> preload([:client, :subscription_plan])
    |> Repo.get!(id)
  end

  def change_client_subscription(%ClientSubscription{} = sub, attrs \\ %{}) do
    ClientSubscription.changeset(sub, attrs)
  end

  def create_client_subscription(attrs \\ %{}) do
    %ClientSubscription{}
    |> ClientSubscription.changeset(attrs)
    |> Repo.insert()
  end

  def update_client_subscription(%ClientSubscription{} = sub, attrs) do
    sub
    |> ClientSubscription.changeset(attrs)
    |> Repo.update()
  end

  @doc "Returns the MRR (in cents) as sum of effective prices on all active/trial subscriptions."
  def mrr_cents do
    active_subs =
      ClientSubscription
      |> where([cs], cs.status in ["active", "trial"])
      |> preload(:subscription_plan)
      |> Repo.all()

    Enum.reduce(active_subs, 0, fn sub, acc ->
      acc + ClientSubscription.effective_price_cents(sub)
    end)
  end
end
