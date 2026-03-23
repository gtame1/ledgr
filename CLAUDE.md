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
