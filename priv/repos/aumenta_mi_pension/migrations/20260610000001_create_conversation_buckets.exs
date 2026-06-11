defmodule Ledgr.Repos.AumentaMiPension.Migrations.CreateConversationBuckets do
  @moduledoc """
  Ledgr-owned operator overlay for AMP conversations, keyed by
  `conversation_id`:

    * six independent boolean tag flags ("buckets"), ticked from the
      checkbox card on the conversation detail page, and
    * `case_notes` — free-text operator comments about the case,
      intended to be surfaced to the bot as additional context (the
      bot service must read this column for that to take effect).

  `conversations` is bot-owned (see CLAUDE.md — we don't write
  migrations against it), so this overlay lives in a separate
  Ledgr-owned table. Same arrangement the retired `conversation_crm`
  table used before CRM moved to `lead_crm`.
  """

  use Ecto.Migration

  def change do
    create table(:conversation_buckets, primary_key: false) do
      add :conversation_id, :string, primary_key: true
      add :asesoria, :boolean, null: false, default: false
      add :demanda, :boolean, null: false, default: false
      add :traspaso_afore, :boolean, null: false, default: false
      add :diagnostico_gratuito, :boolean, null: false, default: false
      add :financiamiento_retroactivo, :boolean, null: false, default: false
      add :credito_pensionado, :boolean, null: false, default: false
      add :case_notes, :text
      timestamps(type: :utc_datetime)
    end
  end
end
