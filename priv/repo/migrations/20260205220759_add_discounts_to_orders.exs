defmodule Ledgr.Repo.Migrations.AddDiscountsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      # "flat" or "percentage", nil means no discount
      add :discount_type, :string
      # peso amount or percentage value
      add :discount_value, :decimal
    end
  end
end
