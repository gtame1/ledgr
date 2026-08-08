# Ledgr — Claude Guidelines

## Local dev setup

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

Every domain works against a local Postgres out of the box. Domains whose data is
owned by an external service (HelloDoctor, Aumenta Mi Pensión, Escuela de Dinero)
fall back to an empty local database and print which one they bound to on boot —
read that line before debugging a page that renders all zeros.

To see real data for one of those, put its URL in `config/dev.secret.exs`
(gitignored, imported before the repo config blocks so `System.put_env/2` works):

```elixir
import Config
System.put_env("ESCUELA_DE_DINERO_DATABASE_URL", "postgresql://…")
```

Migrations that build on externally-owned tables must guard on those tables
existing — see `bot_tables_present?/0` in
`priv/repos/hello_doctor/migrations/20260801120000_create_analytics_fct_consultation.exs`
and the AMP `create_lead_crm` backfill. Without the guard, `mix ecto.migrate`
fails for that repo, and because `Phoenix.Ecto.CheckRepoStatus` checks *every*
configured repo, the whole app 503s for every domain rather than just that one.

## Adding a new app/repo

When adding a new business domain (e.g. "Acme Co"), follow this checklist:

1. **Create the Ecto repo** at `lib/ledgr/repos/<app_name>.ex`

2. **Add it to `config/config.exs`** under `ecto_repos`

3. **Add dev/test config** in `config/dev.exs` and `config/test.exs`

4. **Add conditional prod config** in `config/runtime.exs` — only configure if the env var is present:
   ```elixir
   if url = System.get_env("ACME_CO_DATABASE_URL") do
     config :ledgr, Ledgr.Repos.AcmeCo,
       url: url,
       ssl: [verify: :verify_none, server_name_indication: to_charlist(URI.parse(url).host || "")],
       pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
       priv: "priv/repos/acme_co"
   end
   ```

5. **Add to the optional repos list in `lib/ledgr/application.ex`** — repos only start when their env var is set. This prevents Postgrex connection spam in environments where the DB doesn't exist:
   ```elixir
   optional_repos = [
     ...
     {"ACME_CO_DATABASE_URL", Ledgr.Repos.AcmeCo},
     ...
   ]
   ```

   `Ledgr.Repos.MrMunchMe` is the only always-on repo (it falls back to `DATABASE_URL`).

6. **Register the repo ↔ domain mapping** in `lib/ledgr/repo.ex` (`repo_for_domain/1`). Domains without an explicit clause fall through to `Ledgr.Repos.MrMunchMe` — easy to miss and hard to debug (queries silently hit the wrong DB).

7. **Wire the slug** in `lib/ledgr_web/plugs/domain_plug.ex`'s `@domain_slugs` map.

## Standard sidebar + nav for new domains

The default sidebar is a flat nav with Material Symbols icons, driven entirely by CSS vars from `domain.theme()`. **No per-domain CSS is needed** — just implement two optional callbacks:

```elixir
@impl Ledgr.Domain.DomainConfig
def sidebar_subtitle, do: "Short tagline"

@impl Ledgr.Domain.DomainConfig
def nav_icons do
  %{
    "Dashboard" => "dashboard",
    "Customers" => "group",
    "Payments" => "payments"
    # ... map every menu label to a Material Symbols name
    # https://fonts.google.com/icons
  }
end
```

Active-item accent color comes from `theme().accent` (fallback `theme().primary`). Any domain that implements `nav_icons/0` automatically gets the standard look; domains without it fall back to the legacy dropdown nav.

Reference implementations: `Ledgr.Domains.HelloDoctor`, `Ledgr.Domains.AumentaMiPension`.

## Aumenta Mi Pensión — schema ownership

The AMP database is shared with the external bot service. Two writers, one Postgres:

- **Bot owns** (don't write Ecto migrations for these — apply changes via the bot's migration tooling, then sync the Ecto schema here):
  `agents`, `agent_assistant_messages`, `calculadora_submissions`, `checkup_responses`,
  `consultations`, `consultation_calls`, `conversations`, `customers`, `messages`,
  `outbound_messages`, `payments`, `pension_cases`, `webhook_dedup`.

- **Ledgr owns** (managed via `priv/repos/aumenta_mi_pension/migrations`):
  `stripe_payments`, `users`, `accounts`, `journal_entries`, `journal_lines`,
  `app_settings`, `customer_deletions`.

When you spot drift between the bot DB and our Ecto schemas, update the schema files in `lib/ledgr/domains/aumenta_mi_pension/<table>/` — don't write a migration. `Ledgr.Repos.AumentaMiPension` is configured with `priv: "priv/repos/aumenta_mi_pension"` so `mix ecto.migrate` only sees ledgr-owned migrations.

## Escuela de Dinero — schema ownership

The bot (`escuela-de-dinero-bot`, FastAPI + SQLModel, Alembic) owns **everything
except `users`**. Ledgr reads and never writes: the domain has zero POST routes.

- **Bot owns** — `people`, `conversations`, `messages`, `diagnosticos`, `movimientos`,
  `kubo_referrals`, `policing_events`, `outbound_messages`, plus `checkins`,
  `alert_events`, `webhook_dedup` and the three `experiment_*` tables (all six of
  those have no production writer yet, so we don't mirror them).

- **Ledgr owns** — `users`, and only `users`. There are deliberately no
  `accounts` / `journal_entries` / `app_settings` migrations: this domain is
  operational-only and routes no financial pages, so nothing reads them.

Run `mix edd.schema_drift` (CI, and before trusting any page) to diff the mirrors
in `lib/ledgr/domains/escuela_de_dinero/<table>/` against the live database. When
it reports drift, fix the **schema file** — never write a migration for a
bot-owned table.

Two things about this domain that surprise people:

- **It is the first domain whose `/` is not `ReportController`.** It skips the
  `core_routes*` macros entirely. That's safe only because implementing
  `nav_icons/0` suppresses the shared Reports/Reconciliation/Other nav groups in
  `root.html.heex` — which also makes `menu_items/0` the *sole* source of
  navigation, so a page missing from it is unreachable. A test pins both.

- **Bot timestamps are `TIMESTAMPTZ`, unlike AMP's mirrors.** Schemas use
  `:utc_datetime`, date-range bounds are built in `America/Mexico_City`, and
  daily buckets go through `AT TIME ZONE` before the `::date` cast. Copy AMP's
  naive-datetime idiom here and every chart silently shifts by six hours.
