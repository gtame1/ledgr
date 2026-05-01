defmodule Ledgr.Repo.Migrations.CreateJournalLines do
  use Ecto.Migration

  def change do
    create table(:journal_lines) do
      add :journal_entry_id, references(:journal_entries, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :restrict), null: false

      add :description, :string
      add :debit_cents, :integer, default: 0, null: false
      add :credit_cents, :integer, default: 0, null: false

      timestamps()
    end

    create index(:journal_lines, [:journal_entry_id])
    create index(:journal_lines, [:account_id])

    create constraint(:journal_lines, :non_negative_amounts,
             check: "debit_cents >= 0 AND credit_cents >= 0"
           )

    create constraint(:journal_lines, :non_zero_line,
             check: "debit_cents > 0 OR credit_cents > 0"
           )
  end
end
