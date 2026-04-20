defmodule Ledgr.Domains.MrMunchMe.Orders.StripeShippingFix do
  @moduledoc """
  One-off corrective routine for orders whose Stripe OrderPayments incorrectly
  included shipping.

  Context: prior to the fix in `Orders.create_orders_from_pending_checkout/3`,
  a Stripe checkout with delivery spawned one order per cart line, each stamped
  with `customer_paid_shipping: true` and a per-order payment equal to
  `product_total + shipping`. Shipping was never actually charged by Stripe, so
  the sum of per-order payments exceeded Stripe's real `amount_total`.

  This module re-aligns all sibling orders sharing the same
  `stripe_checkout_session_id` with the actual Stripe amount.
  """

  import Ecto.Query
  require Logger

  alias Ledgr.Repo
  alias Ledgr.Domains.MrMunchMe.{OrderAccounting, Orders}
  alias Ledgr.Domains.MrMunchMe.Orders.{Order, OrderPayment}

  @doc """
  Fixes a single order (and any siblings that share its Stripe session).

  Options:
    * `:fix` — when true, applies the correction. Default `false` (dry-run).

  Prints a summary to stdout so it can be reviewed via `bin/ledgr eval`.
  """
  def run(order_id, opts \\ []) when is_integer(order_id) do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.MrMunchMe)
    fix_mode = Keyword.get(opts, :fix, false)

    order = Repo.get!(Order, order_id)

    session_id =
      order.stripe_checkout_session_id ||
        raise "Order ##{order_id} has no stripe_checkout_session_id"

    siblings =
      from(o in Order,
        where: o.stripe_checkout_session_id == ^session_id,
        order_by: o.id,
        preload: [:variant, :order_payments]
      )
      |> Repo.all()

    IO.puts("\n=== Fix Stripe Shipping Overpayment ===\n")
    IO.puts("Stripe session: #{session_id}")
    IO.puts("Sibling orders: #{Enum.map_join(siblings, ", ", &"##{&1.id}")}\n")

    {:ok, session} = Stripe.Checkout.Session.retrieve(session_id)
    stripe_total = session.amount_total
    IO.puts("Stripe amount_total: #{cents(stripe_total)}\n")

    product_totals =
      Enum.map(siblings, fn o ->
        %{product_total_cents: pt} = Orders.payment_summary_from_preloaded(o)
        pt
      end)

    sum_products = Enum.sum(product_totals)
    allocations = allocate(stripe_total, product_totals, sum_products)

    IO.puts(
      pad("Order", 8) <>
        pad("Paid shipping?", 18) <>
        pad("Product total", 18) <>
        pad("Current payment", 18) <>
        "New payment"
    )

    plan =
      siblings
      |> Enum.zip(Enum.zip(product_totals, allocations))
      |> Enum.map(fn {order, {product_total, new_amount}} ->
        stripe_payment = find_stripe_payment(order)
        current_amount = stripe_payment && stripe_payment.amount_cents

        IO.puts(
          pad("##{order.id}", 8) <>
            pad("#{order.customer_paid_shipping}", 18) <>
            pad(cents(product_total), 18) <>
            pad(cents(current_amount || 0), 18) <>
            cents(new_amount)
        )

        {order, stripe_payment, new_amount}
      end)

    if fix_mode do
      IO.puts("\nApplying corrections...\n")

      Repo.transaction(fn ->
        Enum.each(plan, fn {order, stripe_payment, new_amount} ->
          if order.customer_paid_shipping do
            {:ok, _} =
              order
              |> Order.changeset(%{"customer_paid_shipping" => false})
              |> Repo.update()

            IO.puts("  Order ##{order.id}: customer_paid_shipping -> false")
          end

          cond do
            is_nil(stripe_payment) ->
              IO.puts("  Order ##{order.id}: no Stripe payment row - skipping payment update")

            stripe_payment.amount_cents == new_amount ->
              IO.puts("  Order ##{order.id}: payment already correct (#{cents(new_amount)})")

            true ->
              {:ok, updated} =
                stripe_payment
                |> OrderPayment.changeset(%{"amount_cents" => new_amount})
                |> Repo.update()

              {:ok, _} = OrderAccounting.update_order_payment_journal_entry(updated)

              IO.puts(
                "  Order ##{order.id}: payment ##{stripe_payment.id} -> #{cents(new_amount)} (journal synced)"
              )
          end
        end)
      end)

      IO.puts("\nDone.")
    else
      IO.puts("\nDRY RUN. Re-run with fix: true to apply.")
    end

    IO.puts("")
    :ok
  end

  defp find_stripe_payment(%Order{order_payments: payments}) do
    Enum.find(payments, &(&1.method == "stripe"))
  end

  defp allocate(total_cents, weights, sum_weights) when sum_weights > 0 do
    n = length(weights)

    head =
      weights
      |> Enum.take(n - 1)
      |> Enum.map(fn w -> round(total_cents * w / sum_weights) end)

    head ++ [total_cents - Enum.sum(head)]
  end

  defp allocate(total_cents, weights, _) do
    [total_cents | List.duplicate(0, length(weights) - 1)]
  end

  defp cents(nil), do: "-"
  defp cents(c) when is_integer(c), do: "$#{:erlang.float_to_binary(c / 100, decimals: 2)}"
  defp pad(s, n), do: String.pad_trailing(s, n)
end
