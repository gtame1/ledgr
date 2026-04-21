# Ledgr — Claude Guidelines

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
