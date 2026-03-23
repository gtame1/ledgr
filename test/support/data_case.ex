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
    pid1 = Ecto.Adapters.SQL.Sandbox.start_owner!(Ledgr.Repos.MrMunchMe, shared: not tags[:async])
    pid2 = Ecto.Adapters.SQL.Sandbox.start_owner!(Ledgr.Repos.Viaxe, shared: not tags[:async])
    pid3 = Ecto.Adapters.SQL.Sandbox.start_owner!(Ledgr.Repos.VolumeStudio, shared: not tags[:async])

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid1)
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid2)
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid3)
    end)

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
