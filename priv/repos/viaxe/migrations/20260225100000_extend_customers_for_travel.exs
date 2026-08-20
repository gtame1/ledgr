defmodule Ledgr.Repos.Viaxe.Migrations.ExtendCustomersForTravel do
  use Ecto.Migration

  def change do
    # ── Alter customers: split name, drop delivery_address ───
    rename table(:customers), :name, to: :first_name

    alter table(:customers) do
      add :middle_name, :string
      add :last_name, :string
      add :maternal_last_name, :string
      remove :delivery_address, :text
    end

    # ── Customer Travel Profiles (one-to-one extension) ──────
    create table(:customer_travel_profiles) do
      add :customer_id, references(:customers, on_delete: :delete_all), null: false
      add :dob, :date
      add :gender, :string           # male, female, other, prefer_not_to_say
      add :nationality, :string      # country code e.g. "MX", "US"
      add :home_address, :text
      add :tsa_precheck_number, :string   # Known Traveler Number
      add :seat_preference, :string       # window, aisle, middle, no_preference
      add :meal_preference, :string       # regular, vegetarian, vegan, halal, kosher, gluten_free
      add :medical_notes, :text           # allergies, vaccines, special needs
      add :emergency_contact_name, :string
      add :emergency_contact_phone, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:customer_travel_profiles, [:customer_id])
  end
end
