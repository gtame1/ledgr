defmodule Ledgr.Repos.HelloDoctor.Migrations.AddPostingToExternalCosts do
  use Ecto.Migration

  def change do
    alter table(:external_costs) do
      add :posted_at,        :utc_datetime
      add :journal_entry_id, :integer         # soft reference — GL entries live in same DB
      add :fx_rate,          :float           # MXN/USD rate used at posting time
      add :amount_mxn_cents, :integer         # amount_usd * fx_rate * 100, set at post time
    end
  end
end
