defmodule Ledgr.Repos.HelloDoctor.Migrations.AddReferralLinkToDoctors do
  use Ecto.Migration

  @moduledoc """
  Mirrors the bot's precomputed `referral_link` column on `doctors`
  (the wa.me click-to-chat deep link embedding the doctor's
  extension code). Bot-owned; the column already exists in prod from
  the bot's own startup-time migration. `IF NOT EXISTS` keeps local
  dev DBs in sync without touching prod.
  """

  def up do
    execute("ALTER TABLE doctors ADD COLUMN IF NOT EXISTS referral_link VARCHAR")
  end

  def down do
    # Bot owns the column — don't drop on rollback.
    :ok
  end
end
