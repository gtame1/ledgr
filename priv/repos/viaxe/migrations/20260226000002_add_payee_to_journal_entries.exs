defmodule Ledgr.Repos.Viaxe.Migrations.AddPayeeToJournalEntries do
  use Ecto.Migration

  def change do
    alter table(:journal_entries) do
      add :payee, :string
    end
  end
end
