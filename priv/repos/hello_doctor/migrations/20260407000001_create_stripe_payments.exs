defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateStripePayments do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:stripe_payments) do
      add :stripe_session_id, :string, null: false
      add :stripe_payment_intent_id, :string
      add :amount, :float, null: false
      add :currency, :string, default: "mxn"
      add :status, :string, default: "paid"
      add :customer_email, :string
      add :customer_name, :string
      add :consultation_id, :string
      add :stripe_fee, :float
      add :paid_at, :naive_datetime, null: false

      timestamps()
    end

    create_if_not_exists unique_index(:stripe_payments, [:stripe_session_id])
    create_if_not_exists index(:stripe_payments, [:consultation_id])
    create_if_not_exists index(:stripe_payments, [:paid_at])
  end
end
