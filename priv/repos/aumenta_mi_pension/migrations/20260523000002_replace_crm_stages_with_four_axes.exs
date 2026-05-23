defmodule Ledgr.Repos.AumentaMiPension.Migrations.ReplaceCrmStagesWithFourAxes do
  @moduledoc """
  Restructure the operator-driven CRM overlay to mirror the bot's
  planned four-axis state model. Replaces the original two-stage flat
  fields (`contact_stage`, `sales_stage`) with four orthogonal axes:
  `funnel_stage`, `qualification_verdict`, `escalation_status`,
  `engagement_health`.

  All four are nullable strings — operators set whichever axes they
  have a read on. Allow-list validation lives in the Ecto changeset,
  not as a DB check constraint, since the specific value sets are
  expected to evolve during the bot redesign.
  """

  use Ecto.Migration

  def change do
    alter table(:conversation_crm) do
      remove :contact_stage, :string
      remove :sales_stage, :string
      add :funnel_stage, :string
      add :qualification_verdict, :string
      add :escalation_status, :string
      add :engagement_health, :string
    end
  end
end
