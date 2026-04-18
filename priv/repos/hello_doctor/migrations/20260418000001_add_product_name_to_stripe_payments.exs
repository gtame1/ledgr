defmodule Ledgr.Repos.HelloDoctor.Migrations.AddProductNameToStripePayments do
  use Ecto.Migration

  def change do
    alter table(:stripe_payments) do
      add_if_not_exists :product_name, :string
    end
  end
end
