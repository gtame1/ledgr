defmodule Ledgr.Repos.AumentaMiPension.Migrations.CreateLeadCrm do
  @moduledoc """
  Lift the operator-driven CRM overlay from per-conversation to
  per-lead. Replaces `conversation_crm` (keyed by `conversation_id`)
  with `lead_crm` (keyed by normalized 10-digit phone).

  Backfills the new table by joining `conversation_crm` →
  `conversations` → `customers.phone`, normalizing via
  `Ledgr.Domains.AumentaMiPension.Phones.normalize/1`, and collapsing
  multiple conversation_crm rows for the same phone to the row with
  the latest `updated_at`.

  ## Data loss

  Two cases lose annotations:

    * `conversation_crm` rows whose conversation's customer has
      `phone IS NULL` or an unparseable phone (none currently in the
      dev branch sample, but possible). These rows drop on the floor;
      the count is logged.
    * Multiple `conversation_crm` rows that collapse to the same
      normalized phone — older annotations are superseded by the
      latest (by `updated_at`).

  Both are acceptable: in the new world, annotations are per-lead, so
  the most-recent intent is the canonical one. The legacy table is
  dropped at the end so there's no half-state to clean up.

  ## Down migration

  `down` recreates the empty `conversation_crm` table for structure
  parity only — it does NOT restore annotations. Roll-back is a
  break-glass operation; if you need the data back you're recovering
  from a Postgres backup, not running `mix ecto.rollback`.
  """

  use Ecto.Migration

  alias Ledgr.Domains.AumentaMiPension.Phones

  @six_fields ~w(
    contact_stage sales_stage funnel_stage
    qualification_verdict escalation_status engagement_health
  )

  def up do
    create table(:lead_crm) do
      add :phone, :string, null: false
      add :contact_stage, :string
      add :sales_stage, :string
      add :funnel_stage, :string
      add :qualification_verdict, :string
      add :escalation_status, :string
      add :engagement_health, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:lead_crm, [:phone])

    flush()

    backfill_lead_crm_from_conversation_crm()

    drop table(:conversation_crm)
  end

  def down do
    create table(:conversation_crm) do
      add :conversation_id, :string, null: false
      add :contact_stage, :string
      add :sales_stage, :string
      add :funnel_stage, :string
      add :qualification_verdict, :string
      add :escalation_status, :string
      add :engagement_health, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:conversation_crm, [:conversation_id])

    drop table(:lead_crm)
  end

  defp backfill_lead_crm_from_conversation_crm do
    # Pull every conversation_crm row with its associated customer.phone.
    # Raw SQL because the Ecto schemas may not align at migration time
    # (we're between `conversation_crm` and `lead_crm`).
    sql = """
    SELECT cust.phone AS raw_phone,
           cc.contact_stage, cc.sales_stage, cc.funnel_stage,
           cc.qualification_verdict, cc.escalation_status, cc.engagement_health,
           cc.inserted_at, cc.updated_at
    FROM conversation_crm cc
    JOIN conversations c ON c.id = cc.conversation_id
    JOIN customers cust ON cust.id = c.customer_id
    """

    %{rows: rows, columns: columns} = repo().query!(sql)

    rows
    |> Enum.map(&row_to_map(&1, columns))
    |> Enum.map(&Map.put(&1, "phone", Phones.normalize(&1["raw_phone"])))
    |> tap(&log_unparseable/1)
    |> Enum.reject(&is_nil(&1["phone"]))
    |> Enum.group_by(& &1["phone"])
    |> Enum.map(fn {_phone, rows_for_phone} ->
      Enum.max_by(rows_for_phone, & &1["updated_at"])
    end)
    |> Enum.each(&insert_lead_crm_row/1)
  end

  defp row_to_map(row, columns) do
    Enum.zip(columns, row) |> Map.new()
  end

  defp log_unparseable(rows) do
    unparseable = Enum.count(rows, &is_nil(&1["phone"]))

    if unparseable > 0 do
      IO.puts(
        :stderr,
        "[migration] Dropped #{unparseable} conversation_crm rows " <>
          "with unparseable customer.phone (no normalized form available)."
      )
    end

    rows
  end

  defp insert_lead_crm_row(row) do
    values = Enum.map(@six_fields, &row[&1])

    repo().query!(
      """
      INSERT INTO lead_crm
        (phone, contact_stage, sales_stage, funnel_stage,
         qualification_verdict, escalation_status, engagement_health,
         inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      ON CONFLICT (phone) DO NOTHING
      """,
      [row["phone"] | values] ++ [row["inserted_at"], row["updated_at"]]
    )
  end

end
