defmodule Ledgr.Repos.HelloDoctor.Migrations.RelaxMarketingCostsUniqueness do
  use Ecto.Migration

  @moduledoc """
  Ad billing has MANY charges per platform per day — e.g. one Meta charge per
  ad set, several Google charges/day. The original one-row-per-(platform,date)
  unique indexes wrongly rejected those as duplicates. Drop them; de-duplication
  now happens in the importer on the full charge tuple (platform, date,
  description, amount), skipping only rows already present.
  """

  def up do
    drop_if_exists(
      index(:marketing_costs, [:platform, :date, :source],
        name: :marketing_costs_platform_date_source_idx
      )
    )

    drop_if_exists(
      index(:marketing_costs, [:platform, :date, :source, :campaign_id],
        name: :marketing_costs_platform_date_source_campaign_idx
      )
    )

    create_if_not_exists(index(:marketing_costs, [:platform, :date]))
  end

  def down do
    drop_if_exists(index(:marketing_costs, [:platform, :date]))

    create(
      unique_index(:marketing_costs, [:platform, :date, :source],
        where: "campaign_id IS NULL",
        name: :marketing_costs_platform_date_source_idx
      )
    )

    create(
      unique_index(:marketing_costs, [:platform, :date, :source, :campaign_id],
        where: "campaign_id IS NOT NULL",
        name: :marketing_costs_platform_date_source_campaign_idx
      )
    )
  end
end
