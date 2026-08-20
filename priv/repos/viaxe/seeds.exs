# Set the active repo for Viaxe
Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)

# Load core seeds (shared across all domains)
Code.eval_file("priv/repos/mr_munch_me/seeds/core_seeds.exs")

# Load Viaxe domain seeds
seed_file = "priv/repos/viaxe/seeds/viaxe_seeds.exs"

if File.exists?(seed_file) do
  IO.puts("Loading Viaxe domain seeds: #{seed_file}")
  Code.eval_file(seed_file)
end

# Create default admin user
alias Ledgr.Core.Accounts

admin_email = System.get_env("ADMIN_EMAIL") || "admin@viaxe.com"
admin_password = System.get_env("ADMIN_PASSWORD") || "password123!"

case Accounts.get_user_by_email(admin_email) do
  nil ->
    {:ok, _user} = Accounts.create_user(%{email: admin_email, password: admin_password})
    IO.puts("Created Viaxe admin user: #{admin_email}")

  _user ->
    IO.puts("Viaxe admin user already exists: #{admin_email}")
end
