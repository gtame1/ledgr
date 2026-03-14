defmodule Ledgr.Repos.VolumeStudio.Migrations.AddDiscountToSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      add :discount_cents, :integer, default: 0, null: false
    end
  end
end
