defmodule Ledgr.Domains.VolumeStudio.Subscriptions do
  @moduledoc """
  Context module for managing Volume Studio subscriptions.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting
  alias Ledgr.Domains.VolumeStudio.ClassSessions.ClassBooking
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry

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
  Records a subscription payment for the given amount.

  In a transaction:
    1. Adds amount_cents to deferred_revenue_cents on the subscription
    2. Creates journal entry: DR Cash / CR Deferred Sub Revenue

  Options:
    - `:payment_date` — defaults to today
    - `:method`       — payment method string (e.g. "cash", "card")
    - `:note`         — optional note for the journal entry line

  The subscription must have subscription_plan preloaded.
  """
  def record_payment(sub, amount_cents, opts \\ [])

  def record_payment(%Subscription{subscription_plan: plan} = sub, amount_cents, opts)
      when not is_nil(plan) and is_integer(amount_cents) and amount_cents > 0 do
    Repo.transaction(fn ->
      updated =
        sub
        |> Subscription.changeset(%{
          deferred_revenue_cents: sub.deferred_revenue_cents + amount_cents
        })
        |> Repo.update!()

      VolumeStudioAccounting.record_subscription_payment(sub, amount_cents, opts)

      updated
    end)
  end

  def record_payment(%Subscription{} = sub, amount_cents, opts) do
    # Plan not preloaded — reload and retry
    sub
    |> Repo.preload(:subscription_plan)
    |> record_payment(amount_cents, opts)
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

  @doc """
  Reduces the revenue balances on a subscription to reflect an issued refund.

  Deducts from `deferred_revenue_cents` first; if the refund exceeds the deferred balance,
  the remainder is deducted from `recognized_revenue_cents`.
  """
  def apply_refund(%Subscription{} = sub, refund_cents) do
    deferred_portion   = min(refund_cents, sub.deferred_revenue_cents)
    recognized_portion = refund_cents - deferred_portion

    sub
    |> Subscription.changeset(%{
      deferred_revenue_cents:   sub.deferred_revenue_cents   - deferred_portion,
      recognized_revenue_cents: sub.recognized_revenue_cents - recognized_portion
    })
    |> Repo.update()
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

  Keys: :deferred, :recognized, :total_paid, :remaining, :discount_cents, :effective_price, :outstanding_cents
  """
  def payment_summary(%Subscription{subscription_plan: plan} = sub) when not is_nil(plan) do
    total_paid      = Subscription.total_paid_cents(sub)
    discount        = sub.discount_cents || 0
    effective_price = max(plan.price_cents - discount, 0)

    %{
      deferred:          sub.deferred_revenue_cents,
      recognized:        sub.recognized_revenue_cents,
      total_paid:        total_paid,
      remaining:         Subscription.remaining_deferred(sub),
      discount_cents:    discount,
      effective_price:   effective_price,
      outstanding_cents: max(effective_price - total_paid, 0)
    }
  end

  def payment_summary(%Subscription{} = sub) do
    sub
    |> Repo.preload(:subscription_plan)
    |> payment_summary()
  end

  @doc """
  Returns all subscription_payment journal entries for a given subscription,
  newest first.  Each entry has :journal_lines preloaded with :account.
  """
  def list_payments_for_subscription(%Subscription{id: sub_id}) do
    prefix = "vs_sub_payment_#{sub_id}_%"

    from(je in JournalEntry,
      where: je.entry_type == "subscription_payment",
      where: like(je.reference, ^prefix),
      order_by: [desc: je.date, desc: je.inserted_at],
      preload: [journal_lines: :account]
    )
    |> Repo.all()
  end

  @doc """
  Returns all class bookings linked to a subscription, newest first.
  Each booking has :class_session preloaded.
  """
  def list_bookings_for_subscription(%Subscription{id: sub_id}) do
    from(cb in ClassBooking,
      where: cb.subscription_id == ^sub_id,
      order_by: [desc: cb.inserted_at],
      preload: [class_session: :instructor]
    )
    |> Repo.all()
  end

  @doc """
  Deletes a subscription payment journal entry and rolls back deferred_revenue_cents.

  In a transaction:
    1. Reads the payment amount from the DR (debit) journal line
    2. Subtracts that amount from deferred_revenue_cents on the subscription
    3. Deletes the journal entry (cascade deletes its lines)
  """
  def delete_payment(%Subscription{} = sub, %JournalEntry{} = entry) do
    amount_cents =
      entry.journal_lines
      |> Enum.find(&(&1.debit_cents > 0))
      |> case do
        nil -> 0
        line -> line.debit_cents
      end

    Repo.transaction(fn ->
      sub
      |> Subscription.changeset(%{
        deferred_revenue_cents: max(sub.deferred_revenue_cents - amount_cents, 0)
      })
      |> Repo.update!()

      Repo.delete!(entry)
    end)
  end

  @doc """
  Updates the amount (and optionally date/description) of an existing payment entry.

  In a transaction:
    1. Adjusts deferred_revenue_cents by (new_amount - old_amount)
    2. Replaces the journal lines with updated amounts
  """
  def update_payment(%Subscription{} = sub, %JournalEntry{} = entry, attrs) do
    new_amount_cents = Map.fetch!(attrs, :amount_cents)
    new_date         = Map.get(attrs, :payment_date, entry.date)
    new_note         = Map.get(attrs, :note)

    old_amount_cents =
      entry.journal_lines
      |> Enum.find(&(&1.debit_cents > 0))
      |> case do
        nil -> 0
        line -> line.debit_cents
      end

    diff = new_amount_cents - old_amount_cents

    cash_account     = Accounting.get_account_by_code!("1000")
    deferred_account = Accounting.get_account_by_code!("2200")

    Repo.transaction(fn ->
      sub
      |> Subscription.changeset(%{
        deferred_revenue_cents: sub.deferred_revenue_cents + diff
      })
      |> Repo.update!()

      case Accounting.update_journal_entry_with_lines(
        entry,
        %{date: new_date, description: entry.description},
        [
          %{account_id: cash_account.id,     debit_cents: new_amount_cents, credit_cents: 0,
            description: new_note || "Cash received — subscription ##{sub.id}"},
          %{account_id: deferred_account.id, debit_cents: 0, credit_cents: new_amount_cents,
            description: "Deferred subscription revenue — sub ##{sub.id}"}
        ]
      ) do
        {:ok, updated_entry} -> updated_entry
        {:error, reason}     -> Repo.rollback(reason)
      end
    end)
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp maybe_filter_customer(query, nil), do: query
  defp maybe_filter_customer(query, id), do: where(query, customer_id: ^id)
end
