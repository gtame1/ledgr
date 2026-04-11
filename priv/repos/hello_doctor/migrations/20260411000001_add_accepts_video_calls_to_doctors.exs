defmodule Ledgr.Repos.HelloDoctor.Migrations.AddAcceptsVideoCallsToDoctors do
  use Ecto.Migration

  def change do
    alter table(:doctors) do
      add_if_not_exists :accepts_video_calls, :boolean, default: true
    end
  end
end
