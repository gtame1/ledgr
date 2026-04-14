defmodule Ledgr.Repos.HelloDoctor.Migrations.AddConversationNewFields do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add_if_not_exists :stripe_payment_intent_id, :string
      add_if_not_exists :consultation_type, :string
    end
  end
end
