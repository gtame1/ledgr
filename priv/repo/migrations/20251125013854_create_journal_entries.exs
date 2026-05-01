defmodule Ledgr.Repo.Migrations.CreateJournalEntries do
  use Ecto.Migration

  def change do
    create table(:journal_entries) do
      add :date, :date, null: false
      add :description, :text, null: false
      add :reference, :string
      add :entry_type, :string, null: false

      timestamps()
    end

    create index(:journal_entries, [:date])
  end
end
