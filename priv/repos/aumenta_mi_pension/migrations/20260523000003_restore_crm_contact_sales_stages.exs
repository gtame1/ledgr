defmodule Ledgr.Repos.AumentaMiPension.Migrations.RestoreCrmContactSalesStages do
  @moduledoc """
  Restore the original CRM pipeline columns (`contact_stage`,
  `sales_stage`) on `conversation_crm` alongside the four-axis state
  fields added in `20260523000002_replace_crm_stages_with_four_axes`.

  These two are **independent** of the four axes — they represent the
  operator's traditional CRM pipeline view (where in the contact/sales
  funnel this lead sits), separate from the operator's overlay of the
  bot's state machine.

  Both nullable; allow-list validation lives in the Ecto changeset.
  """

  use Ecto.Migration

  def change do
    alter table(:conversation_crm) do
      add :contact_stage, :string
      add :sales_stage, :string
    end
  end
end
