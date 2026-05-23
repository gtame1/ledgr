defmodule Ledgr.Repos.AumentaMiPension.Migrations.CreateConversationCrm do
  use Ecto.Migration

  @moduledoc """
  Ledgr-owned CRM overlay for AMP conversations. One row per conversation,
  keyed by `conversation_id` (no DB-level FK because the `conversations`
  table is owned by the bot service — see CLAUDE.md "Aumenta Mi Pensión —
  schema ownership").
  """

  def change do
    create table(:conversation_crm) do
      add :conversation_id, :string, null: false
      add :contact_stage, :string
      add :sales_stage, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:conversation_crm, [:conversation_id])
  end
end
