defmodule Ledgr.Repos.Viaxe.Migrations.CreateTravelDocuments do
  use Ecto.Migration

  def change do
    # ── Passports ────────────────────────────────────────────
    create table(:passports) do
      add :customer_id, references(:customers, on_delete: :restrict), null: false
      add :country, :string, null: false     # issuing country code e.g. "MX"
      add :number, :string, null: false
      add :issue_date, :date
      add :expiry_date, :date
      add :is_primary, :boolean, default: false, null: false
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:passports, [:customer_id])
    create index(:passports, [:expiry_date])

    # ── Customer Visas ───────────────────────────────────────
    create table(:customer_visas) do
      add :customer_id, references(:customers, on_delete: :restrict), null: false
      add :country, :string, null: false     # destination country code
      add :visa_type, :string                # tourist, work, student, transit, multiple_entry
      add :visa_number, :string
      add :issue_date, :date
      add :expiry_date, :date
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:customer_visas, [:customer_id])
    create index(:customer_visas, [:expiry_date])

    # ── Loyalty Programs ─────────────────────────────────────
    create table(:loyalty_programs) do
      add :customer_id, references(:customers, on_delete: :restrict), null: false
      add :program_name, :string, null: false   # e.g. "AAdvantage", "Marriott Bonvoy"
      add :program_type, :string                # airline, hotel, car_rental, other
      add :member_number, :string, null: false
      add :tier, :string                        # Gold, Platinum, Elite, etc.
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:loyalty_programs, [:customer_id])
  end
end
