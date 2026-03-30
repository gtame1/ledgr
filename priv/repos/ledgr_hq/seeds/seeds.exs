# Seeds for Ledgr HQ domain
# Idempotent — safe to run multiple times.

alias Ledgr.Repos.LedgrHQ, as: Repo
alias Ledgr.Domains.LedgrHQ.SubscriptionPlans.SubscriptionPlan
alias Ledgr.Domains.LedgrHQ.Clients.Client
alias Ledgr.Domains.LedgrHQ.ClientSubscriptions.ClientSubscription
alias Ledgr.Domains.LedgrHQ.Costs.Cost
alias Ledgr.Core.Accounting.Account
alias Ledgr.Core.Expenses

import Ecto.Query

# Helper: insert or fetch existing by name
get_or_insert! = fn struct, conflict_field ->
  case Repo.insert(struct, on_conflict: :nothing, conflict_target: [conflict_field]) do
    {:ok, %{id: nil}} ->
      # Conflict fired — fetch the existing row
      name = Map.get(struct, conflict_field)
      Repo.one!(from r in struct.__struct__, where: field(r, ^conflict_field) == ^name)
    {:ok, record} ->
      record
  end
end

# ── Subscription Plans ────────────────────────────────────────────

starter = get_or_insert!.(%SubscriptionPlan{name: "Starter", description: "Single-app deployment with basic features", price_cents: 9900, active: true}, :name)
pro = get_or_insert!.(%SubscriptionPlan{name: "Pro", description: "Multi-feature app with full accounting stack", price_cents: 19900, active: true}, :name)
_enterprise = get_or_insert!.(%SubscriptionPlan{name: "Enterprise", description: "Custom multi-domain deployment", price_cents: 49900, active: true}, :name)

IO.puts("✓ Subscription plans seeded")

# ── Clients ───────────────────────────────────────────────────────

mr_munch_me = get_or_insert!.(%Client{name: "MrMunchMe", domain_slug: "mr-munch-me", status: "active", started_on: ~D[2025-11-01]}, :name)
viaxe = get_or_insert!.(%Client{name: "Viaxe", domain_slug: "viaxe", status: "active", started_on: ~D[2026-02-01]}, :name)
volume_studio = get_or_insert!.(%Client{name: "Volume Studio", domain_slug: "volume-studio", status: "active", started_on: ~D[2026-03-01]}, :name)

IO.puts("✓ Clients seeded")

# ── Client Subscriptions ──────────────────────────────────────────

[
  {mr_munch_me.id, pro.id, ~D[2025-11-01]},
  {viaxe.id, starter.id, ~D[2026-02-01]},
  {volume_studio.id, pro.id, ~D[2026-03-01]}
]
|> Enum.each(fn {client_id, plan_id, starts_on} ->
  exists? = Repo.exists?(
    from cs in ClientSubscription,
      where: cs.client_id == ^client_id and cs.subscription_plan_id == ^plan_id and cs.status != "cancelled"
  )

  unless exists? do
    Repo.insert!(%ClientSubscription{
      client_id: client_id,
      subscription_plan_id: plan_id,
      starts_on: starts_on,
      status: "active"
    })
  end
end)

IO.puts("✓ Client subscriptions seeded")

# ── Costs ─────────────────────────────────────────────────────────

[
  %Cost{name: "Fly.io", vendor: "Fly.io", category: "cloud_hosting", amount_cents: 2500, billing_period: "monthly", active: true},
  %Cost{name: "Cloudflare", vendor: "Cloudflare", category: "domain_dns", amount_cents: 1200, billing_period: "annual", active: true, notes: "DNS + domain registration"},
  %Cost{name: "Stripe", vendor: "Stripe", category: "saas_tools", amount_cents: 100, billing_period: "monthly", active: false, notes: "Per-transaction fees, no fixed cost"},
  %Cost{name: "GitHub", vendor: "GitHub", category: "saas_tools", amount_cents: 400, billing_period: "monthly", active: true}
]
|> Enum.each(fn cost ->
  Repo.insert!(cost, on_conflict: :nothing, conflict_target: [:name])
end)

IO.puts("✓ Costs seeded")

# ── Example Expenses ──────────────────────────────────────────────
# Uses the core Expenses module (with journal entries) so the
# accounting ledger stays consistent.

Ledgr.Repo.put_active_repo(Ledgr.Repos.LedgrHQ)

get_account_id = fn code ->
  case Repo.get_by(Account, code: code) do
    nil -> raise "Account #{code} not found — run migrations first"
    acc -> acc.id
  end
end

cash_id = get_account_id.("1000")
contractor_id = get_account_id.("5300")
domain_dns_id = get_account_id.("5110")
marketing_id = get_account_id.("5500")

[
  %{
    date: ~D[2026-03-05],
    description: "Logo design — freelancer",
    amount_cents: 15000,
    category: "contractor",
    payee: "Design Studio MX",
    expense_account_id: contractor_id,
    paid_from_account_id: cash_id
  },
  %{
    date: ~D[2026-03-10],
    description: "ledgr.io domain renewal",
    amount_cents: 1500,
    category: "domain_dns",
    payee: "Cloudflare",
    expense_account_id: domain_dns_id,
    paid_from_account_id: cash_id
  },
  %{
    date: ~D[2026-03-15],
    description: "Meta Ads — March campaign",
    amount_cents: 5000,
    category: "marketing",
    payee: "Meta Platforms",
    expense_account_id: marketing_id,
    paid_from_account_id: cash_id
  }
]
|> Enum.each(fn attrs ->
  # Skip if an expense with same description and date already exists
  exists? = Repo.exists?(
    from e in Ledgr.Core.Expenses.Expense,
      where: e.description == ^attrs.description and e.date == ^attrs.date
  )

  unless exists? do
    Expenses.create_expense(attrs)
  end
end)

IO.puts("✓ Example expenses seeded")

IO.puts("\nLedgr HQ seeding complete ✓")
