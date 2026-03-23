# Seeds for Ledgr HQ domain

alias Ledgr.Repos.LedgrHQ, as: Repo
alias Ledgr.Domains.LedgrHQ.SubscriptionPlans.SubscriptionPlan
alias Ledgr.Domains.LedgrHQ.Clients.Client
alias Ledgr.Domains.LedgrHQ.ClientSubscriptions.ClientSubscription
alias Ledgr.Domains.LedgrHQ.Costs.Cost

# ── Subscription Plans ────────────────────────────────────────────

starter = Repo.insert!(
  %SubscriptionPlan{name: "Starter", description: "Single-app deployment with basic features", price_cents: 9900, active: true},
  on_conflict: :nothing, conflict_target: []
)

pro = Repo.insert!(
  %SubscriptionPlan{name: "Pro", description: "Multi-feature app with full accounting stack", price_cents: 19900, active: true},
  on_conflict: :nothing, conflict_target: []
)

_enterprise = Repo.insert!(
  %SubscriptionPlan{name: "Enterprise", description: "Custom multi-domain deployment", price_cents: 49900, active: true},
  on_conflict: :nothing, conflict_target: []
)

IO.puts("✓ Subscription plans seeded")

# ── Clients ───────────────────────────────────────────────────────

mr_munch_me = Repo.insert!(
  %Client{
    name: "MrMunchMe",
    domain_slug: "mr-munch-me",
    status: "active",
    started_on: ~D[2025-11-01]
  },
  on_conflict: :nothing, conflict_target: []
)

viaxe = Repo.insert!(
  %Client{
    name: "Viaxe",
    domain_slug: "viaxe",
    status: "active",
    started_on: ~D[2026-02-01]
  },
  on_conflict: :nothing, conflict_target: []
)

volume_studio = Repo.insert!(
  %Client{
    name: "Volume Studio",
    domain_slug: "volume-studio",
    status: "active",
    started_on: ~D[2026-03-01]
  },
  on_conflict: :nothing, conflict_target: []
)

IO.puts("✓ Clients seeded")

# ── Client Subscriptions ──────────────────────────────────────────

Repo.insert!(
  %ClientSubscription{
    client_id: mr_munch_me.id,
    subscription_plan_id: pro.id,
    starts_on: ~D[2025-11-01],
    status: "active"
  },
  on_conflict: :nothing, conflict_target: []
)

Repo.insert!(
  %ClientSubscription{
    client_id: viaxe.id,
    subscription_plan_id: starter.id,
    starts_on: ~D[2026-02-01],
    status: "active"
  },
  on_conflict: :nothing, conflict_target: []
)

Repo.insert!(
  %ClientSubscription{
    client_id: volume_studio.id,
    subscription_plan_id: pro.id,
    starts_on: ~D[2026-03-01],
    status: "active"
  },
  on_conflict: :nothing, conflict_target: []
)

IO.puts("✓ Client subscriptions seeded")

# ── Costs ─────────────────────────────────────────────────────────

costs = [
  %Cost{name: "Fly.io", vendor: "Fly.io", category: "cloud_hosting", amount_cents: 2500, billing_period: "monthly", active: true},
  %Cost{name: "Cloudflare", vendor: "Cloudflare", category: "domain_dns", amount_cents: 1200, billing_period: "annual", active: true, notes: "DNS + domain registration"},
  %Cost{name: "Stripe", vendor: "Stripe", category: "saas_tools", amount_cents: 100, billing_period: "monthly", active: false, notes: "Per-transaction fees, no fixed cost"},
  %Cost{name: "GitHub", vendor: "GitHub", category: "saas_tools", amount_cents: 400, billing_period: "monthly", active: true},
]

Enum.each(costs, fn cost ->
  Repo.insert!(cost, on_conflict: :nothing, conflict_target: [])
end)

IO.puts("✓ Costs seeded")

IO.puts("\nLedgr HQ seeding complete ✓")
