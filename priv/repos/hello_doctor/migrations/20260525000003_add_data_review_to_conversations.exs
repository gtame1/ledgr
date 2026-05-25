defmodule Ledgr.Repos.HelloDoctor.Migrations.AddDataReviewToConversations do
  use Ecto.Migration

  # The bot stamps `data_review_sent_at` on `conversations` once the
  # patient's medical record review is sent. Funnel reports use it.
  # IF NOT EXISTS — no-op when the bot's own migrations already created it.

  def up do
    execute(
      "ALTER TABLE conversations ADD COLUMN IF NOT EXISTS data_review_sent_at timestamp"
    )
  end

  def down, do: :ok
end
