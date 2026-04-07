# Production seeds for HelloDoctor — accounts and admin user only, no dummy data.
Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)

# Load core seeds (equity accounts)
Code.eval_file(Application.app_dir(:ledgr, "priv/repos/mr_munch_me/seeds/core_seeds.exs"))

# Load HelloDoctor domain seeds (chart of accounts — sample data is skipped in prod)
Code.eval_file(Application.app_dir(:ledgr, "priv/repos/hello_doctor/seeds/hello_doctor_seeds.exs"))

# Create admin user
admin_email = System.get_env("ADMIN_EMAIL") || "admin@hellodoctor.mx"
admin_password = System.get_env("ADMIN_PASSWORD") || "password123!"

case Ledgr.Core.Accounts.get_user_by_email(admin_email) do
  nil ->
    {:ok, _user} = Ledgr.Core.Accounts.create_user(%{email: admin_email, password: admin_password})
    IO.puts("Created HelloDoctor admin user: #{admin_email}")
  _user ->
    IO.puts("HelloDoctor admin user already exists: #{admin_email}")
end
