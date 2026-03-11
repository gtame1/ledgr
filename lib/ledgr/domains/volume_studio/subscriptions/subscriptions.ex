defmodule Ledgr.Domains.VolumeStudio.Subscriptions do
  @moduledoc """
  Context module for managing Volume Studio subscriptions.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting

  @doc """
  Returns a list of subscriptions.

  Options:
    - `:status` — filter by status string, e.g. "active"
    - `:customer_id` — filter by customer
  """
  def list_subscriptions(opts \\ []) do
    status = Keyword.get(opts, :status)
    customer_id = Keyword.get(opts, :customer_id)

    Subscription
    |> maybe_filter_status(status)
    |> maybe_filter_customer(customer_id)
    |> order_by(desc: :inserted_at)
    |> preload([:customer, :subscription_plan])
    |> Repo.all()
  end

  @doc "Gets a single subscription with customer and plan preloaded. Raises if not found."
  def get_subscription!(id) do
    Subscription
    |> preload([:customer, :subscription_plan])
    |> Repo.get!(id)
  end

  @doc "Returns a changeset for the given subscription and attrs."
  def change_subscription(%Subscription{} = sub, attrs \\ %{}) do
    Subscription.changeset(sub, attrs)
  end

  @doc "Creates a subscription. No journal entry on creation — payment is recorded separately."
  def create_subscription(attrs \\ %{}) do
    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a subscription."
  def update_subscription(%Subscription{} = sub, attrs) do
    sub
    |> Subscription.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Records a subscription payment.

  In a transaction:
    1. Adds plan.price_cents to deferred_revenue_cents
    2. Creates journal entry: DR Cash / CR Deferred Sub Revenue

  The subscription must have subscription_plan preloaded.
  """
  def record_payment(%Subscription{subscription_plan: plan} = sub)
      when not is_nil(plan) do
    Repo.transaction(fn ->
      amount = plan.price_cents

      updated =
        sub
        |> Subscription.changeset(%{
          deferred_revenue_cents: sub.deferred_revenue_cents + amount
        })
        |> Repo.update!()

      VolumeStudioAccounting.record_subscription_payment(sub)

      updated
    end)
  end

  def record_payment(%Subscription{} = sub) do
    # Plan not preloaded — reload with plan and retry
    sub
    |> Repo.preload(:subscription_plan)
    |> record_payment()
  end

  @doc """
  Recognizes a portion of deferred subscription revenue.

  In a transaction:
    1. Moves amount_cents from deferred_revenue_cents → recognized_revenue_cents
    2. Creates journal entry: DR Deferred Sub Revenue / CR Subscription Revenue
  """
  def recognize_revenue(%Subscription{} = sub, amount_cents) when amount_cents > 0 do
    available = sub.deferred_revenue_cents
    to_recognize = min(amount_cents, available)

    if to_recognize <= 0 do
      {:error, :no_deferred_revenue}
    else
      Repo.transaction(fn ->
        updated =
          sub
          |> Subscription.changeset(%{
            deferred_revenue_cents: sub.deferred_revenue_cents - to_recognize,
            recognized_revenue_cents: sub.recognized_revenue_cents + to_recognize
          })
          |> Repo.update!()

        VolumeStudioAccounting.recognize_subscription_revenue(sub, to_recognize)

        updated
      end)
    end
  end

  @doc "Cancels a subscription by updating its status and setting ends_on to today."
  def cancel(%Subscription{} = sub) do
    sub
    |> Subscription.changeset(%{
      status: "cancelled",
      ends_on: Date.utc_today()
    })
    |> Repo.update()
  end

  @doc """
  Returns a payment summary map for a subscription.

  Keys: :deferred, :recognized, :total_paid, :remaining
  """
  def payment_summary(%Subscription{} = sub) do
    %{
      deferred: sub.deferred_revenue_cents,
      recognized: sub.recognized_revenue_cents,
      total_paid: Subscription.total_paid_cents(sub),
      remaining: Subscription.remaining_deferred(sub)
    }
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp maybe_filter_customer(query, nil), do: query
  defp maybe_filter_customer(query, id), do: where(query, customer_id: ^id)
end
