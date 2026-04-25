defmodule Ledgr.Repos.CasaTame.Migrations.CreateExpenseAttachments do
  use Ecto.Migration

  def up do
    create table(:expense_attachments) do
      add :expense_id, references(:expenses, on_delete: :delete_all), null: false
      add :filename, :string, null: false       # original filename shown to user
      add :stored_path, :string, null: false    # path on disk relative to uploads root
      add :content_type, :string
      add :file_size, :integer                  # bytes

      timestamps()
    end

    create index(:expense_attachments, [:expense_id])
  end

  def down do
    drop table(:expense_attachments)
  end
end
