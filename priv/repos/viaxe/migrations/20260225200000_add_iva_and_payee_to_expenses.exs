defmodule Ledgr.Repos.Viaxe.Migrations.AddIvaAndPayeeToExpenses do
  use Ecto.Migration

  def change do
    alter table(:expenses) do
      add :iva_cents, :integer, default: 0
      add :payee, :string
    end
  end
end
