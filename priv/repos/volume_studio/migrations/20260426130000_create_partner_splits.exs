defmodule Ledgr.Repos.VolumeStudio.Migrations.CreatePartnerSplits do
  use Ecto.Migration

  def change do
    create table(:partner_splits) do
      add :name, :string, null: false
      add :notes, :string
      add :deleted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:partner_splits, [:name], where: "deleted_at IS NULL")

    create table(:partner_split_lines) do
      add :partner_split_id, references(:partner_splits, on_delete: :delete_all), null: false
      add :partner_id, references(:partners, on_delete: :restrict), null: false
      add :share_bps, :integer, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:partner_split_lines, [:partner_split_id])
    create unique_index(:partner_split_lines, [:partner_split_id, :partner_id])

    alter table(:subscriptions) do
      add :partner_split_id, references(:partner_splits, on_delete: :nilify_all)
    end

    alter table(:consultations) do
      add :partner_split_id, references(:partner_splits, on_delete: :nilify_all)
    end

    alter table(:space_rentals) do
      add :partner_split_id, references(:partner_splits, on_delete: :nilify_all)
    end

    create table(:expense_partner_splits, primary_key: false) do
      add :expense_id, :bigint, null: false, primary_key: true
      add :partner_split_id, references(:partner_splits, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create index(:expense_partner_splits, [:partner_split_id])
  end
end
