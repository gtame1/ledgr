# Set the active repo for Volume Studio
Ledgr.Repo.put_active_repo(Ledgr.Repos.VolumeStudio)

# Load core seeds (shared across all domains)
Code.eval_file("priv/repos/mr_munch_me/seeds/core_seeds.exs")

# Load Volume Studio domain seeds
seed_file = "priv/repos/volume_studio/seeds/volume_studio_seeds.exs"

if File.exists?(seed_file) do
  IO.puts("Loading Volume Studio domain seeds: #{seed_file}")
  Code.eval_file(seed_file)
end

# Create default admin user
alias Ledgr.Core.Accounts

admin_email = System.get_env("ADMIN_EMAIL") || "admin@volumestudio.com"
admin_password = System.get_env("ADMIN_PASSWORD") || "password123!"

case Accounts.get_user_by_email(admin_email) do
  nil ->
    {:ok, _user} = Accounts.create_user(%{email: admin_email, password: admin_password})
    IO.puts("Created Volume Studio admin user: #{admin_email}")

  _user ->
    IO.puts("Volume Studio admin user already exists: #{admin_email}")
end
