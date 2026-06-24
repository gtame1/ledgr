defmodule Ledgr.Repos.HelloDoctor.Migrations.AddDiscountToStripePayments do
  use Ecto.Migration

  def change do
    alter table(:stripe_payments) do
      # Promotion / coupon code applied at Stripe checkout (e.g. "SALUD26"),
      # or NULL when the customer paid full price. Populated by StripeSync
      # from the Checkout Session's expanded promotion_code.
      add :discount_code, :string
      # Discount amount in MXN (Stripe's total_details.amount_discount / 100).
      add :discount_amount, :float
    end
  end
end
