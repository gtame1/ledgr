defmodule Ledgr.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Ledgr.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Ledgr.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Ledgr.DataCase
    end
  end

  setup tags do
    Ledgr.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    # Every configured repo needs a sandbox owner; keep this list in step with
    # `config :ledgr, :ecto_repos`. A list rather than eight numbered pids so
    # adding or removing a domain is a one-line change.
    owners =
      for repo <- [
            Ledgr.Repos.MrMunchMe,
            Ledgr.Repos.VolumeStudio,
            Ledgr.Repos.CasaTame,
            Ledgr.Repos.HelloDoctor,
            Ledgr.Repos.AumentaMiPension,
            Ledgr.Repos.EscuelaDeDinero
          ] do
        Ecto.Adapters.SQL.Sandbox.start_owner!(repo, shared: not tags[:async])
      end

    on_exit(fn -> Enum.each(owners, &Ecto.Adapters.SQL.Sandbox.stop_owner/1) end)

    # Default to MrMunchMe; domain tests override this in their own setup
    Ledgr.Repo.put_active_repo(Ledgr.Repos.MrMunchMe)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
