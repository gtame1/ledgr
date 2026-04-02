# Set the active repo for Casa Tame
Ledgr.Repo.put_active_repo(Ledgr.Repos.CasaTame)

# Load core seeds (shared across all domains)
Code.eval_file("priv/repos/mr_munch_me/seeds/core_seeds.exs")

# Load Casa Tame domain seeds
seed_file = "priv/repos/casa_tame/seeds/casa_tame_seeds.exs"

if File.exists?(seed_file) do
  IO.puts("Loading Casa Tame domain seeds: #{seed_file}")
  Code.eval_file(seed_file)
end

# Create default admin user
alias Ledgr.Core.Accounts

admin_email = System.get_env("ADMIN_EMAIL") || "admin@casatame.com"
admin_password = System.get_env("ADMIN_PASSWORD") || "password123!"

case Accounts.get_user_by_email(admin_email) do
  nil ->
    {:ok, _user} = Accounts.create_user(%{email: admin_email, password: admin_password})
    IO.puts("Created Casa Tame admin user: #{admin_email}")

  _user ->
    IO.puts("Casa Tame admin user already exists: #{admin_email}")
end
