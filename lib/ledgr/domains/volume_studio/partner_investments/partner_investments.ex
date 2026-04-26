defmodule Ledgr.Domains.VolumeStudio.PartnerInvestments do
  @moduledoc """
  VS-specific aggregations over the shared partners + capital_contributions
  tables. Read-only — no core schemas or contexts are modified.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Core.Partners.{Partner, CapitalContribution}

  @doc """
  Returns one row per partner with total_in_cents, total_out_cents, net_cents,
  and contribution counts.
  """
  def partner_summaries do
    from(p in Partner,
      left_join: c in CapitalContribution,
      on: c.partner_id == p.id,
      group_by: [p.id],
      order_by: p.name,
      select: %{
        partner: p,
        total_in_cents: coalesce(sum(fragment("CASE WHEN ? = 'in'  THEN ? ELSE 0 END", c.direction, c.amount_cents)), 0),
        total_out_cents: coalesce(sum(fragment("CASE WHEN ? = 'out' THEN ? ELSE 0 END", c.direction, c.amount_cents)), 0),
        contribution_count: count(c.id),
        last_activity_on: max(c.date)
      }
    )
    |> Repo.all()
    |> Enum.map(fn row -> Map.put(row, :net_cents, row.total_in_cents - row.total_out_cents) end)
  end

  @doc "Total net capital across all partners, in cents."
  def total_net_cents do
    from(c in CapitalContribution,
      select:
        coalesce(
          sum(
            fragment("CASE WHEN ? = 'out' THEN -? ELSE ? END", c.direction, c.amount_cents, c.amount_cents)
          ),
          0
        )
    )
    |> Repo.one()
  end

  @doc "All capital contributions, newest first, with partner preloaded."
  def list_activity(opts \\ []) do
    limit_n = Keyword.get(opts, :limit, 50)

    from(c in CapitalContribution,
      order_by: [desc: c.date, desc: c.inserted_at],
      preload: :partner,
      limit: ^limit_n
    )
    |> Repo.all()
  end
end
