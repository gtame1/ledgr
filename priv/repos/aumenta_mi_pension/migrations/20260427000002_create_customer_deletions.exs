defmodule Ledgr.Repos.AumentaMiPension.Migrations.CreateCustomerDeletions do
  use Ecto.Migration

  @moduledoc """
  Tombstone table for soft-deleted customers.

  We don't own the upstream `customers` / `conversations` / `messages` tables
  (Python service writes them), so instead of mutating those, we record a
  deletion intent here. The Ledgr UI filters customers whose id appears in
  this table — they're effectively hidden without touching upstream data.
  Restoring is a single DELETE on this table.
  """

  def change do
    create_if_not_exists table(:customer_deletions, primary_key: false) do
      add :customer_id, :string, primary_key: true, null: false
      add :phone, :string
      add :full_name, :string
      add :reason, :string
      add :deleted_by, :string
      add :deleted_at, :utc_datetime, null: false, default: fragment("NOW()")
      timestamps()
    end
  end
end
