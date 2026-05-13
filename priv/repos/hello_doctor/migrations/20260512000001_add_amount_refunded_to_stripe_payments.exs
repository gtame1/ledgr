defmodule Ledgr.Repos.HelloDoctor.Migrations.AddAmountRefundedToStripePayments do
  use Ecto.Migration

  def change do
    alter table(:stripe_payments) do
      add :amount_refunded, :float, default: 0.0, null: false
    end
  end
end
