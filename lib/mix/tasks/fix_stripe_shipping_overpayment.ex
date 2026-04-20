defmodule Mix.Tasks.FixStripeShippingOverpayment do
  @moduledoc """
  Local wrapper around `Ledgr.Domains.MrMunchMe.Orders.StripeShippingFix.run/2`.

  Usage:
    mix fix_stripe_shipping_overpayment --order 225          # Dry run
    mix fix_stripe_shipping_overpayment --order 225 --fix    # Apply

  On production (release builds, no Mix), invoke via:
    bin/ledgr eval 'Ledgr.Release.fix_stripe_shipping_overpayment(225)'
    bin/ledgr eval 'Ledgr.Release.fix_stripe_shipping_overpayment(225, fix: true)'
  """

  use Mix.Task

  @shortdoc "Fix Stripe OrderPayments that double-counted shipping (local dev)"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [order: :integer, fix: :boolean])
    order_id = opts[:order] || Mix.raise("--order <id> is required")

    Ledgr.Domains.MrMunchMe.Orders.StripeShippingFix.run(order_id, fix: opts[:fix] == true)
  end
end
