defmodule Ledgr.Repos.HelloDoctor.Migrations.AddMedikitDoctorFields do
  use Ecto.Migration

  # Per-doctor data required by Medikit's doctors-1.0.38 /doctors + validate
  # endpoints that the doctors table did not previously store. All additive and
  # nullable so existing rows and the bot's writes are unaffected.
  #
  # `medikit_healthcare_provider_id` / `medikit_license_validated_at` were added
  # out-of-band earlier; `add_if_not_exists` makes this migration idempotent
  # against that (no-ops in prod where they already exist, creates them in fresh
  # dev/CI DBs).
  def change do
    alter table(:doctors) do
      # Structured name — feeds validate (firstName/paternalLastName/
      # maternalLastName) and register (FirstName + LastName).
      add_if_not_exists :first_name, :string
      add_if_not_exists :paternal_surname, :string
      add_if_not_exists :maternal_surname, :string

      add_if_not_exists :birthdate, :date
      add_if_not_exists :gender, :string
      add_if_not_exists :tax_id, :string

      # Postal address — per-doctor (Country kept per-doctor for a possible
      # future international expansion; falls back to the :medikit config
      # default, "MX", when blank).
      add_if_not_exists :address_country, :string
      add_if_not_exists :address_state, :string
      add_if_not_exists :address_city, :string
      add_if_not_exists :address_line, :string
      add_if_not_exists :address_zipcode, :string

      # Medikit specialty catalog id (mapped per doctor from the dropdown),
      # distinct from the free-text `specialty`.
      add_if_not_exists :medikit_specialty_id, :string

      # Provisioning result (previously added out-of-band).
      add_if_not_exists :medikit_healthcare_provider_id, :string
      add_if_not_exists :medikit_license_validated_at, :utc_datetime
    end
  end
end
