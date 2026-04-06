defmodule Ledgr.Repos.HelloDoctor do
  use Ecto.Repo,
    otp_app: :ledgr,
    adapter: Ecto.Adapters.Postgres
end
