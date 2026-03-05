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

if viaxe_url = System.get_env("VIAXE_DATABASE_URL") || System.get_env("DATABASE_URL") do
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

# Only configure server when running the app (not when building)
if System.get_env("PHX_SERVER") do
  config :ledgr, LedgrWeb.Endpoint, server: true
end

if volume = System.get_env("UPLOAD_VOLUME") do
  config :ledgr, :upload_dir, "#{volume}/uploads/products"
  config :ledgr, :upload_serve_dir, volume
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE missing"

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ledgr, LedgrWeb.Endpoint,
    url: [host: host, scheme: "https", port: 443],
    http: [ip: {0,0,0,0,0,0,0,0}, port: port],
    secret_key_base: secret_key_base
end
