defmodule Ledgr.Repos.HelloDoctor.Migrations.AddNewDoctorFields do
  use Ecto.Migration

  def change do
    alter table(:doctors) do
      add_if_not_exists :terms_accepted, :boolean, default: false
      add_if_not_exists :terms_accepted_at, :utc_datetime
      add_if_not_exists :extension_code, :string
    end
  end
end
