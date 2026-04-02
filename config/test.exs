import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ledgr, Ledgr.Repos.MrMunchMe,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ledgr_mr_munch_me_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  priv: "priv/repos/mr_munch_me"

config :ledgr, Ledgr.Repos.Viaxe,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ledgr_viaxe_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  priv: "priv/repos/viaxe"

config :ledgr, Ledgr.Repos.VolumeStudio,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ledgr_volume_studio_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  priv: "priv/repos/volume_studio"

config :ledgr, Ledgr.Repos.LedgrHQ,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ledgr_ledgr_hq_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  priv: "priv/repos/ledgr_hq"

config :ledgr, Ledgr.Repos.CasaTame,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ledgr_casa_tame_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  priv: "priv/repos/casa_tame"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ledgr, LedgrWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "LWGiO76eEGRF7BJO7J2CZos1lz9ueVlC7zqWpZgd8Kt46Y34zygeyJ+u9Z/J6ZZQ",
  server: false

# In test we don't send emails
config :ledgr, Ledgr.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
