# Seeds for Ledgr HQ domain
# Run with: mix run priv/repos/ledgr_hq/seeds.exs

# Set the active repo for LedgrHQ
Ledgr.Repo.put_active_repo(Ledgr.Repos.LedgrHQ)

# Load LedgrHQ domain seeds
Code.eval_file("priv/repos/ledgr_hq/seeds/seeds.exs")

# Create default admin user
alias Ledgr.Core.Accounts

admin_email = System.get_env("ADMIN_EMAIL") || "admin@ledgr.io"
admin_password = System.get_env("ADMIN_PASSWORD") || "password123!"

case Accounts.get_user_by_email(admin_email) do
  nil ->
    {:ok, _user} = Accounts.create_user(%{email: admin_email, password: admin_password})
    IO.puts("Created Ledgr HQ admin user: #{admin_email}")

  _user ->
    IO.puts("Ledgr HQ admin user already exists: #{admin_email}")
end
