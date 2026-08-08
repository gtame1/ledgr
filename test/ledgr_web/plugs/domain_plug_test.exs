defmodule LedgrWeb.Plugs.DomainPlugTest do
  @moduledoc """
  What happens when a domain ships without its database.

  In production every repo but MrMunchMe starts only if its `*_DATABASE_URL` is
  set. Forget the variable and the domain's routes still deploy — so the first
  query raises `could not lookup Ecto repo ... because it was not started` and
  *every* page, login included, is a 500 with a stacktrace. These tests pin the
  503 that replaces it, and the wiring that decides which repo a domain gets.
  """
  use LedgrWeb.ConnCase, async: false

  describe "when the domain's repo was never started" do
    setup do
      # Unregistering the name is exactly what the application sees when the
      # repo was skipped at boot — without tearing down a live pool that other
      # tests would need. LedgrHQ has no page tests of its own.
      pid = Process.whereis(Ledgr.Repos.LedgrHQ)
      Process.unregister(Ledgr.Repos.LedgrHQ)
      on_exit(fn -> Process.register(pid, Ledgr.Repos.LedgrHQ) end)
      :ok
    end

    test "the request 503s instead of raising", %{conn: conn} do
      conn = get(conn, "/app/ledgr/login")

      assert conn.status == 503
      assert conn.halted
      assert conn.resp_body =~ Ledgr.Domains.LedgrHQ.name()
    end

    test "the domain context is never set, so no query can reach a dead repo", %{conn: conn} do
      conn = get(conn, "/app/ledgr/login")

      refute conn.assigns[:current_domain]
    end
  end

  describe "repo wiring" do
    test "started?/1 tracks whether the repo is actually running" do
      assert Ledgr.Repo.started?(Ledgr.Repos.MrMunchMe)
      refute Ledgr.Repo.started?(Ledgr.Repos.NotARepo)
    end

    test "every routable domain maps to a repo the application knows how to start" do
      # repo_for_domain/1 falls through to MrMunchMe for unregistered domains,
      # so a missing clause reads as "works" until queries hit the wrong DB.
      # And a repo absent from @optional_repos never starts in production.
      for {slug, domain} <- LedgrWeb.Plugs.DomainPlug.domain_slugs() do
        repo = Ledgr.Repo.repo_for_domain(domain)

        assert repo in Ledgr.Repo.all_repos(),
               "#{slug} resolves to #{inspect(repo)}, which is not in Ledgr.Repo.all_repos/0"

        if repo != Ledgr.Repos.MrMunchMe do
          assert Ledgr.Repo.env_var_for(repo),
                 "#{slug} resolves to #{inspect(repo)}, which has no *_DATABASE_URL entry in " <>
                   "Ledgr.Repo.optional_repos/0 — it would never start in production"
        end
      end
    end
  end
end
