defmodule Ledgr.Release do
  @moduledoc """
  Release tasks for running migrations and seeds in production.

  ## Usage

      # Run on every deploy (via Render preDeployCommand):
      bin/ledgr eval "Ledgr.Release.migrate()"

      # Run once after first deploy to seed required business data:
      bin/ledgr eval "Ledgr.Release.seed()"

      # Or via the named release commands (defined in mix.exs):
      bin/ledgr migrate
      bin/ledgr seed
      bin/ledgr rollback_seeds
  """

  @app :ledgr

  # Production seed files — real business data only, no dummy/sample records.
  @prod_seed_paths %{
    Ledgr.Repos.MrMunchMe   => "priv/repos/mr_munch_me/seeds_prod.exs",
    Ledgr.Repos.Viaxe       => "priv/repos/viaxe/seeds_prod.exs",
    Ledgr.Repos.CasaTame    => "priv/repos/casa_tame/seeds_prod.exs",
    Ledgr.Repos.HelloDoctor => "priv/repos/hello_doctor/seeds_prod.exs"
  }

  @doc """
  Runs all pending Ecto migrations for every configured repo.

  Called on every deploy via Render's preDeployCommand. Safe to run
  repeatedly — Ecto skips already-applied migrations.

  Resilience behaviour:
  - Repos with no database URL in config are skipped gracefully.
  - Repos whose URL is set but whose database is unreachable (expired,
    wrong credentials, network issue) are caught and logged as warnings;
    the remaining repos still migrate normally.
  - All per-repo outcomes are summarised at the end.
  """
  def migrate do
    IO.puts("==> Running migrations...")
    load_app()

    results =
      Enum.map(repos(), fn repo ->
        if repo_configured?(repo) do
          IO.puts("    Migrating #{inspect(repo)}...")

          try do
            {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
            IO.puts("    #{inspect(repo)} — done.")
            {:ok, repo}
          rescue
            e ->
              IO.puts("    ⚠  #{inspect(repo)} FAILED: #{Exception.message(e)}")
              IO.puts("       Skipping this repo — other repos will still migrate.")
              {:error, repo, e}
          end
        else
          IO.puts("    Skipping #{inspect(repo)} — no database URL configured.")
          {:skipped, repo}
        end
      end)

    failed = for {:error, repo, _} <- results, do: repo

    if failed == [] do
      IO.puts("==> Migrations complete.")
    else
      IO.puts("")
      IO.puts("==> Migrations finished with warnings. The following repos could not be migrated:")
      Enum.each(failed, fn repo -> IO.puts("      • #{inspect(repo)}") end)
      IO.puts("    Check the database URL and connectivity for these repos.")
    end
  end

  @doc """
  Seeds required production data for all repos (chart of accounts, products,
  ingredients, recipes, suppliers, services, admin user).

  Run ONCE after the first deploy — or after a database reset.
  Safe to run again (all seeds are idempotent).
  """
  def seed do
    IO.puts("==> Running production seeds...")
    {:ok, _} = Application.ensure_all_started(@app)

    for {repo, seed_path} <- @prod_seed_paths do
      full_path = Application.app_dir(@app, seed_path)

      if File.exists?(full_path) do
        IO.puts("    Seeding #{inspect(repo)} from #{seed_path}...")
        Ledgr.Repo.put_active_repo(repo)
        Code.eval_file(full_path)
        IO.puts("    Done seeding #{inspect(repo)}.")
      else
        IO.puts("    WARNING: seed file not found for #{inspect(repo)}: #{full_path}")
      end
    end

    IO.puts("==> Seeds complete.")
  end

  @doc """
  Removes all seeded master data from both repos, leaving the chart of
  accounts untouched.

  ⚠️  This deletes ALL records in the affected tables — including any
  real data created on top of the seeds (orders, inventory movements, etc.).
  Only run this when you want a full reset before re-seeding.

  Deletion follows FK dependency order (children before parents).
  """
  def rollback_seeds do
    IO.puts("==> Rolling back production seeds (chart of accounts retained)...")
    {:ok, _} = Application.ensure_all_started(@app)

    rollback_mr_munch_me()
    rollback_viaxe()

    IO.puts("==> Rollback complete. Run `bin/ledgr seed` to re-seed.")
  end

  @doc """
  One-off fix for Stripe orders whose OrderPayments double-counted shipping.
  Delegates to `Ledgr.Domains.MrMunchMe.Orders.StripeShippingFix.run/2`.

  Callable from a release shell:
      bin/ledgr eval 'Ledgr.Release.fix_stripe_shipping_overpayment(225)'
      bin/ledgr eval 'Ledgr.Release.fix_stripe_shipping_overpayment(225, fix: true)'
  """
  def fix_stripe_shipping_overpayment(order_id, opts \\ []) do
    {:ok, _} = Application.ensure_all_started(@app)
    Ledgr.Domains.MrMunchMe.Orders.StripeShippingFix.run(order_id, opts)
  end

  # ── Private ──────────────────────────────────────────────

  defp rollback_mr_munch_me do
    IO.puts("    Clearing MrMunchMe seed data...")
    Ledgr.Repo.put_active_repo(Ledgr.Repos.MrMunchMe)
    repo = Ledgr.Repos.MrMunchMe

    deletes = [
      # Order children
      {Ledgr.Domains.MrMunchMe.Orders.OrderIngredient, "order ingredients"},
      {Ledgr.Domains.MrMunchMe.Orders.OrderPayment,    "order payments"},
      {Ledgr.Domains.MrMunchMe.Orders.Order,           "orders"},
      # Recipe children
      {Ledgr.Domains.MrMunchMe.Inventory.RecipeLine,   "recipe lines"},
      {Ledgr.Domains.MrMunchMe.Inventory.Recipe,       "recipes"},
      # Inventory children
      {Ledgr.Domains.MrMunchMe.Inventory.InventoryMovement, "inventory movements"},
      {Ledgr.Domains.MrMunchMe.Inventory.InventoryItem,     "inventory items"},
      # Product children
      {Ledgr.Domains.MrMunchMe.Orders.ProductImage, "product images"},
      # Master data (parents)
      {Ledgr.Domains.MrMunchMe.Orders.Product,          "products"},
      {Ledgr.Domains.MrMunchMe.Inventory.Ingredient,    "ingredients"},
      {Ledgr.Domains.MrMunchMe.Inventory.Location,      "inventory locations"},
      {Ledgr.Core.Partners.CapitalContribution,         "capital contributions"},
      {Ledgr.Core.Partners.Partner,                     "partners"},
      {Ledgr.Core.Accounts.User,                        "users"}
    ]

    for {schema, label} <- deletes do
      {n, _} = repo.delete_all(schema)
      IO.puts("      #{n} #{label} deleted")
    end
  end

  defp rollback_viaxe do
    IO.puts("    Clearing Viaxe seed data...")
    Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)
    repo = Ledgr.Repos.Viaxe

    deletes = [
      {Ledgr.Domains.Viaxe.Services.Service,   "services"},
      {Ledgr.Domains.Viaxe.Suppliers.Supplier, "suppliers"},
      {Ledgr.Core.Accounts.User,               "users"}
    ]

    for {schema, label} <- deletes do
      {n, _} = repo.delete_all(schema)
      IO.puts("      #{n} #{label} deleted")
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  # Returns true only if the repo has a :url key in its runtime config.
  # Repos with no database URL configured (e.g. an expired Render DB whose
  # env var was removed) are skipped gracefully rather than timing out.
  defp repo_configured?(repo) do
    case Application.fetch_env(@app, repo) do
      {:ok, config} -> Keyword.has_key?(config, :url)
      :error        -> false
    end
  end

  # Loads the app's module tree and runtime config without starting any
  # GenServers or connection pools. Used by migrate/0 so that
  # Ecto.Migrator.with_repo/2 can start each repo temporarily — with its
  # own minimal pool — rather than competing with the full supervision tree.
  defp load_app do
    Application.load(@app)
  end
end
