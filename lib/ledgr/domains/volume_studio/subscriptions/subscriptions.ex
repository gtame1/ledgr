defmodule Ledgr.Domains.VolumeStudio.Subscriptions do
  @moduledoc """
  Context module for managing Volume Studio subscriptions.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans.SubscriptionPlan
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting
  alias Ledgr.Domains.VolumeStudio.ClassSessions.ClassBooking
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry

  @doc """
  Returns a list of subscriptions.

  Options:
    - `:status` — filter by status string, e.g. "active"
    - `:customer_id` — filter by customer
    - `:plan_type` — filter by plan type, e.g. "extra"
  """
  def list_subscriptions(opts \\ []) do
    status = Keyword.get(opts, :status)
    customer_id = Keyword.get(opts, :customer_id)
    plan_type = Keyword.get(opts, :plan_type)

    Subscription
    |> where([s], is_nil(s.deleted_at))
    |> maybe_filter_status(status)
    |> maybe_filter_customer(customer_id)
    |> maybe_filter_plan_type(plan_type)
    |> order_by(desc: :inserted_at)
    |> preload([:customer, :subscription_plan])
    |> Repo.all()
  end

  @doc "Gets a single subscription with customer and plan preloaded. Raises if not found."
  def get_subscription!(id) do
    from(s in Subscription, where: s.id == ^id and is_nil(s.deleted_at))
    |> preload([:customer, :subscription_plan])
    |> Repo.one!()
  end

  @doc "Returns a changeset for the given subscription and attrs."
  def change_subscription(%Subscription{} = sub, attrs \\ %{}) do
    Subscription.changeset(sub, attrs)
  end

  @doc "Creates a subscription. No journal entry on creation — payment is recorded separately."
  def create_subscription(attrs \\ %{}) do
    plan_id  = Map.get(attrs, "subscription_plan_id") || Map.get(attrs, :subscription_plan_id)
    discount = coerce_int(Map.get(attrs, "discount_cents") || Map.get(attrs, :discount_cents) || 0)
    iva      = compute_iva_cents(plan_id, discount)

    %Subscription{}
    |> Subscription.changeset(Map.merge(coerce_string_keys(attrs), %{"iva_cents" => iva}))
    |> Repo.insert()
  end

  @doc "Updates a subscription. Recomputes iva_cents if plan or discount changes."
  def update_subscription(%Subscription{} = sub, attrs) do
    plan_changing     = Map.has_key?(attrs, "subscription_plan_id") or Map.has_key?(attrs, :subscription_plan_id)
    discount_changing = Map.has_key?(attrs, "discount_cents") or Map.has_key?(attrs, :discount_cents)

    attrs_with_iva =
      if plan_changing or discount_changing do
        plan_id  = Map.get(attrs, "subscription_plan_id") || Map.get(attrs, :subscription_plan_id) || sub.subscription_plan_id
        discount = coerce_int(Map.get(attrs, "discount_cents") || Map.get(attrs, :discount_cents) || sub.discount_cents || 0)
        iva      = compute_iva_cents(plan_id, discount)
        Map.merge(coerce_string_keys(attrs), %{"iva_cents" => iva})
      else
        attrs
      end

    sub
    |> Subscription.changeset(attrs_with_iva)
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

  def record_payment(%Subscription{subscription_plan: %Ecto.Association.NotLoaded{}} = sub, amount_cents, opts) do
    sub
    |> Repo.preload(:subscription_plan)
    |> record_payment(amount_cents, opts)
  end

  def record_payment(%Subscription{subscription_plan: plan} = sub, amount_cents, opts)
      when not is_nil(plan) and is_integer(amount_cents) and amount_cents > 0 do
    {base_portion, _iva_portion} = split_base_iva(sub, amount_cents)

    Repo.transaction(fn ->
      updated =
        sub
        |> Subscription.changeset(%{
          deferred_revenue_cents: sub.deferred_revenue_cents + base_portion,
          paid_cents:             (sub.paid_cents || 0) + amount_cents
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
    recognized_portion = max(refund_cents - deferred_portion, 0)

    sub
    |> Subscription.changeset(%{
      deferred_revenue_cents:   sub.deferred_revenue_cents   - deferred_portion,
      recognized_revenue_cents: sub.recognized_revenue_cents - recognized_portion,
      paid_cents:               max((sub.paid_cents || 0) - refund_cents, 0)
    })
    |> Repo.update()
  end

  @doc """
  Marks an extra-type subscription as redeemed (service delivered).

  Increments `classes_used` and, if deferred revenue is available, immediately
  recognizes it — the equivalent of a class check-in for non-class extras
  (consultations, merchandise, drop-ins sold outside the class schedule).
  """
  def redeem_extra(%Subscription{subscription_plan: plan} = sub) when not is_nil(plan) do
    Repo.transaction(fn ->
      updated =
        sub
        |> Ecto.Changeset.change(classes_used: sub.classes_used + 1)
        |> Repo.update!()

      if sub.deferred_revenue_cents > 0 do
        to_recognize = sub.deferred_revenue_cents

        updated
        |> Ecto.Changeset.change(
          deferred_revenue_cents:   0,
          recognized_revenue_cents: updated.recognized_revenue_cents + to_recognize
        )
        |> Repo.update!()

        VolumeStudioAccounting.recognize_subscription_revenue(sub, to_recognize)
      end

      updated
    end)
  end

  @doc """
  Cancels a subscription by updating its status and setting ends_on to today.

  In a transaction:
    1. Updates status → "cancelled" and ends_on → today
    2. If any deferred_revenue_cents remain, recognizes them immediately as
       Subscription Revenue (4000) — the studio retains unrefunded prepayments.
  """
  def cancel(%Subscription{} = sub) do
    Repo.transaction(fn ->
      updated =
        sub
        |> Subscription.changeset(%{status: "cancelled", ends_on: Date.utc_today()})
        |> Repo.update!()

      if updated.deferred_revenue_cents > 0 do
        amount = updated.deferred_revenue_cents

        updated
        |> Subscription.changeset(%{
          deferred_revenue_cents:   0,
          recognized_revenue_cents: updated.recognized_revenue_cents + amount
        })
        |> Repo.update!()

        VolumeStudioAccounting.recognize_subscription_revenue(updated, amount)
      end

      updated
    end)
  end

  @doc """
  Finalizes a subscription by setting its status to `new_status` ("completed" or
  "expired") and immediately recognizing any remaining deferred revenue.

  Mirrors the behaviour of `cancel/1` — the studio has delivered (or is owed)
  the full value of whatever was prepaid, so nothing stays deferred once the
  subscription is done.

  In a transaction:
    1. Updates status → new_status
    2. If any deferred_revenue_cents remain, recognizes them as Subscription Revenue (4000).
  """
  def finalize(%Subscription{} = sub, new_status) when new_status in ["completed", "expired"] do
    Repo.transaction(fn ->
      updated =
        sub
        |> Subscription.changeset(%{status: new_status})
        |> Repo.update!()

      if updated.deferred_revenue_cents > 0 do
        amount = updated.deferred_revenue_cents

        updated
        |> Subscription.changeset(%{
          deferred_revenue_cents:   0,
          recognized_revenue_cents: updated.recognized_revenue_cents + amount
        })
        |> Repo.update!()

        VolumeStudioAccounting.recognize_subscription_revenue(updated, amount)
      end

      updated
    end)
  end

  @doc """
  Returns a payment summary map for a subscription.

  Keys: :deferred, :recognized, :total_paid, :remaining, :discount_cents, :effective_price, :outstanding_cents
  """
  def payment_summary(%Subscription{subscription_plan: %Ecto.Association.NotLoaded{}} = sub) do
    sub
    |> Repo.preload(:subscription_plan)
    |> payment_summary()
  end

  def payment_summary(%Subscription{subscription_plan: plan} = sub) when not is_nil(plan) do
    base     = plan.price_cents
    discount = sub.discount_cents || 0
    iva      = sub.iva_cents || 0
    base_eff = max(base - discount, 0)
    total    = base_eff + iva
    paid     = sub.paid_cents || 0

    %{
      base_cents:        base,
      iva_cents:         iva,
      discount_cents:    discount,
      effective_price:   base_eff,
      total_cents:       total,
      total_paid:        paid,
      deferred:          sub.deferred_revenue_cents,
      recognized:        sub.recognized_revenue_cents,
      remaining:         Subscription.remaining_deferred(sub),
      outstanding_cents: max(total - paid, 0)
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
  Reverses a subscription payment journal entry and rolls back deferred_revenue_cents.

  In a transaction:
    1. Reads the payment amount from the DR (debit) journal line
    2. Subtracts that amount from deferred_revenue_cents and paid_cents on the subscription
    3. Creates a reversing journal entry (original entry is preserved for audit trail)
  """
  def delete_payment(%Subscription{} = sub, %JournalEntry{} = entry) do
    entry_with_lines =
      if Ecto.assoc_loaded?(entry.journal_lines) do
        entry
      else
        Repo.preload(entry, :journal_lines)
      end

    amount_cents =
      entry_with_lines.journal_lines
      |> Enum.find(&(&1.debit_cents > 0))
      |> case do
        nil -> 0
        line -> line.debit_cents
      end

    {base_portion, _} = split_base_iva(sub, amount_cents)

    Repo.transaction(fn ->
      sub
      |> Subscription.changeset(%{
        deferred_revenue_cents: max(sub.deferred_revenue_cents - base_portion, 0),
        paid_cents:             max((sub.paid_cents || 0) - amount_cents, 0)
      })
      |> Repo.update!()

      case VolumeStudioAccounting.reverse_subscription_payment(entry_with_lines) do
        {:ok, _reversal}  -> :ok
        {:error, reason}  -> Repo.rollback(reason)
      end
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

    {old_base, _} = split_base_iva(sub, old_amount_cents)
    {new_base, new_iva} = split_base_iva(sub, new_amount_cents)

    deferred_diff = new_base - old_base
    paid_diff     = new_amount_cents - old_amount_cents

    cash_account     = Accounting.get_account_by_code!("1000")
    deferred_account = Accounting.get_account_by_code!("2200")

    base_lines = [
      %{account_id: cash_account.id,     debit_cents: new_amount_cents, credit_cents: 0,
        description: new_note || "Cash received — subscription ##{sub.id}"},
      %{account_id: deferred_account.id, debit_cents: 0, credit_cents: new_base,
        description: "Deferred subscription revenue — sub ##{sub.id}"}
    ]

    lines =
      if new_iva > 0 do
        iva_account = Accounting.get_account_by_code!("2100")
        base_lines ++ [
          %{account_id: iva_account.id, debit_cents: 0, credit_cents: new_iva,
            description: "IVA payable — sub ##{sub.id}"}
        ]
      else
        base_lines
      end

    Repo.transaction(fn ->
      sub
      |> Subscription.changeset(%{
        deferred_revenue_cents: sub.deferred_revenue_cents + deferred_diff,
        paid_cents:             (sub.paid_cents || 0) + paid_diff
      })
      |> Repo.update!()

      case Accounting.update_journal_entry_with_lines(
        entry,
        %{date: new_date, description: entry.description},
        lines
      ) do
        {:ok, updated_entry} -> updated_entry
        {:error, reason}     -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Returns the active subscription closest to expiring for a customer
  that still has classes available (or has no class limit).

  Skips subscriptions whose `ends_on` is in the past, whose status is not
  "active", or that have hit their plan's class_limit.

  Returns `nil` if no eligible subscription exists.
  """
  def get_soonest_expiring_subscription(customer_id) do
    today = Date.utc_today()

    Subscription
    |> where(customer_id: ^customer_id, status: "active")
    |> where([s], s.ends_on >= ^today)
    |> preload(:subscription_plan)
    |> Repo.all()
    |> Enum.filter(fn sub ->
      plan = sub.subscription_plan
      is_nil(plan.class_limit) or sub.classes_used < plan.class_limit
    end)
    |> Enum.min_by(& &1.ends_on, Date, fn -> nil end)
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp maybe_filter_customer(query, nil), do: query
  defp maybe_filter_customer(query, id), do: where(query, customer_id: ^id)

  defp maybe_filter_plan_type(query, nil), do: query
  defp maybe_filter_plan_type(query, type) do
    query
    |> join(:inner, [s], sp in assoc(s, :subscription_plan), as: :plan)
    |> where([s, plan: sp], sp.plan_type == ^type)
  end

  # Returns {base_portion, iva_portion} for a given payment amount,
  # using the proportional split of the subscription's stored iva_cents.
  defp split_base_iva(%Subscription{subscription_plan: plan} = sub, amount_cents)
       when not is_nil(plan) do
    base  = max(plan.price_cents - (sub.discount_cents || 0), 0)
    iva   = sub.iva_cents || 0
    total = base + iva

    if total > 0 do
      b = round(amount_cents * base / total)
      {b, amount_cents - b}
    else
      {amount_cents, 0}
    end
  end

  defp split_base_iva(%Subscription{} = sub, amount_cents) do
    sub = Repo.preload(sub, :subscription_plan)
    split_base_iva(sub, amount_cents)
  end

  # Computes IVA (16%) on effective base price for a given plan + discount.
  defp compute_iva_cents(nil, _discount), do: 0
  defp compute_iva_cents("", _discount), do: 0

  defp compute_iva_cents(plan_id, discount) do
    case Repo.get(SubscriptionPlan, plan_id) do
      nil  -> 0
      plan -> round(max(plan.price_cents - discount, 0) * 0.16)
    end
  end

  # Coerces integer / string to integer (returns 0 on failure).
  defp coerce_int(v) when is_integer(v), do: v
  defp coerce_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error  -> 0
    end
  end
  defp coerce_int(_), do: 0

  # Ensures map keys are strings for consistent merging with form params.
  defp coerce_string_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
