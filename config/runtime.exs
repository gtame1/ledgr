import Config

# Configure repos from DATABASE_URLs if provided (for production/staging)
# For local development, use dev.exs configuration instead
if mr_munch_me_url = System.get_env("MR_MUNCH_ME_DATABASE_URL") || System.get_env("DATABASE_URL") do
  db_uri = URI.parse(mr_munch_me_url)

  config :ledgr, Ledgr.Repos.MrMunchMe,
    url: mr_munch_me_url,
    ssl: [
      verify: :verify_none,
      server_name_indication: to_charlist(db_uri.host || "")
    ],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
    priv: "priv/repos/mr_munch_me"
end

if viaxe_url = System.get_env("VIAXE_DATABASE_URL") do
  db_uri = URI.parse(viaxe_url)

  config :ledgr, Ledgr.Repos.Viaxe,
    url: viaxe_url,
    ssl: [
      verify: :verify_none,
      server_name_indication: to_charlist(db_uri.host || "")
    ],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
    priv: "priv/repos/viaxe"
end

if volume_studio_url = System.get_env("VOLUME_STUDIO_DATABASE_URL") do
  db_uri = URI.parse(volume_studio_url)

  config :ledgr, Ledgr.Repos.VolumeStudio,
    url: volume_studio_url,
    ssl: [
      verify: :verify_none,
      server_name_indication: to_charlist(db_uri.host || "")
    ],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
    priv: "priv/repos/volume_studio"
end

if ledgr_hq_url = System.get_env("LEDGR_HQ_DATABASE_URL") do
  db_uri = URI.parse(ledgr_hq_url)

  config :ledgr, Ledgr.Repos.LedgrHQ,
    url: ledgr_hq_url,
    ssl: [
      verify: :verify_none,
      server_name_indication: to_charlist(db_uri.host || "")
    ],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
    priv: "priv/repos/ledgr_hq"
end

if casa_tame_url = System.get_env("CASA_TAME_DATABASE_URL") do
  db_uri = URI.parse(casa_tame_url)

  config :ledgr, Ledgr.Repos.CasaTame,
    url: casa_tame_url,
    ssl: [
      verify: :verify_none,
      server_name_indication: to_charlist(db_uri.host || "")
    ],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
    priv: "priv/repos/casa_tame"
end

if hello_doctor_url = System.get_env("HELLO_DOCTOR_DATABASE_URL") do
  db_uri = URI.parse(hello_doctor_url)

  config :ledgr, Ledgr.Repos.HelloDoctor,
    url: hello_doctor_url,
    ssl: [
      verify: :verify_none,
      server_name_indication: to_charlist(db_uri.host || "")
    ],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
    priv: "priv/repos/hello_doctor"
end

if aumenta_mi_pension_url = System.get_env("AUMENTA_MI_PENSION_DATABASE_URL") do
  db_uri = URI.parse(aumenta_mi_pension_url)

  config :ledgr, Ledgr.Repos.AumentaMiPension,
    url: aumenta_mi_pension_url,
    ssl: [
      verify: :verify_none,
      server_name_indication: to_charlist(db_uri.host || "")
    ],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
    priv: "priv/repos/aumenta_mi_pension"
end

# Domain hostname → slug mapping for production routing.
# DomainPlug uses this to detect the active domain from the request Host header,
# allowing each business to run on its own domain (e.g. volumestudio.com).
# Set DOMAIN_HOSTS as a comma-separated list: "hostname:slug,hostname:slug"
# Example: "mrmunchme.com:mr-munch-me,volumestudio.com:volume-studio,viaxe.com:viaxe"
if domain_hosts_env = System.get_env("DOMAIN_HOSTS") do
  hosts =
    domain_hosts_env
    |> String.split(",", trim: true)
    |> Enum.map(fn pair ->
      [host, slug] = String.split(pair, ":", parts: 2)
      {String.trim(host), String.trim(slug)}
    end)
    |> Map.new()

  config :ledgr, :domain_hosts, hosts
end

# Only configure server when running the app (not when building)
if System.get_env("PHX_SERVER") do
  config :ledgr, LedgrWeb.Endpoint, server: true
end

if volume = System.get_env("UPLOAD_VOLUME") do
  config :ledgr, :upload_dir, "#{volume}/uploads/products"
  # Plug.Static strips the `at:` prefix ("/uploads") then looks in `from:`.
  # So `from:` must be the parent of the "uploads" directory on disk.
  config :ledgr, :upload_serve_dir, "#{volume}/uploads"
end

# Stripe payment processing (env vars override dev.secret.exs in production)
if stripe_key = System.get_env("STRIPE_SECRET_KEY") do
  config :stripity_stripe, api_key: stripe_key
end

if webhook_secret = System.get_env("STRIPE_WEBHOOK_SECRET") do
  config :ledgr, stripe_webhook_secret: webhook_secret
end

# HelloDoctor Stripe (separate account)
if hd_stripe_key = System.get_env("HELLO_DOCTOR_STRIPE_SECRET_KEY") do
  config :ledgr, hello_doctor_stripe_api_key: hd_stripe_key
end

if hd_webhook_secret = System.get_env("HELLO_DOCTOR_STRIPE_WEBHOOK_SECRET") do
  config :ledgr, hello_doctor_stripe_webhook_secret: hd_webhook_secret
end

# HelloDoctor external billing API keys
if key = System.get_env("HELLO_DOCTOR_OPENAI_API_KEY") do
  config :ledgr, hello_doctor_openai_api_key: key
end

if key = System.get_env("HELLO_DOCTOR_WHEREBY_API_KEY") do
  config :ledgr, hello_doctor_whereby_api_key: key
end

if key = System.get_env("HELLO_DOCTOR_AWS_ACCESS_KEY_ID") do
  config :ledgr, hello_doctor_aws_access_key_id: key
end

if key = System.get_env("HELLO_DOCTOR_AWS_SECRET_ACCESS_KEY") do
  config :ledgr, hello_doctor_aws_secret_access_key: key
end

# Aumenta Mi Pensión Stripe (separate account)
if amp_stripe_key = System.get_env("AUMENTA_MI_PENSION_STRIPE_SECRET_KEY") do
  config :ledgr, aumenta_mi_pension_stripe_api_key: amp_stripe_key
end

if amp_webhook_secret = System.get_env("AUMENTA_MI_PENSION_STRIPE_WEBHOOK_SECRET") do
  config :ledgr, aumenta_mi_pension_stripe_webhook_secret: amp_webhook_secret
end

# AMP bot service admin endpoints (FastAPI). Used for customer reset.
if amp_bot_url = System.get_env("AUMENTA_MI_PENSION_BOT_URL") do
  config :ledgr, aumenta_mi_pension_bot_url: amp_bot_url
end

if amp_bot_key = System.get_env("AUMENTA_MI_PENSION_BOT_ADMIN_API_KEY") do
  config :ledgr, aumenta_mi_pension_bot_admin_api_key: amp_bot_key
end

# Prescrypto digital prescriptions — only override when env var is explicitly set
# (dev uses dev.secret.exs with the sandbox token; prod sets PRESCRYPTO_TOKEN)
if token = System.get_env("PRESCRYPTO_TOKEN") do
  config :ledgr, :prescrypto,
    base_url: System.get_env("PRESCRYPTO_BASE_URL", "https://prescrypto.com/"),
    token: token,
    enabled: true
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE missing"

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ledgr, LedgrWeb.Endpoint,
    url: [host: host, scheme: "https", port: 443],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
