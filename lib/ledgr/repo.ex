defmodule Ledgr.Repo do
  @moduledoc """
  Dynamic repo wrapper that delegates to the active repo based on
  the current domain (set via process dictionary).

  In production, the active repo is set per-request by DomainPlug.
  In tests, it's set in DataCase.setup_sandbox/1.
  """

  @doc "Returns the currently active concrete repo module."
  def active_repo do
    Process.get(:ledgr_repo) || default_repo()
  end

  @doc "Sets the active repo for the current process."
  def put_active_repo(repo_module) do
    Process.put(:ledgr_repo, repo_module)
  end

  defp default_repo do
    domain = Application.get_env(:ledgr, :domain)
    repo_for_domain(domain)
  end

  @doc "Returns the repo module for a given domain module."
  def repo_for_domain(Ledgr.Domains.MrMunchMe), do: Ledgr.Repos.MrMunchMe
  def repo_for_domain(Ledgr.Domains.Viaxe), do: Ledgr.Repos.Viaxe
  def repo_for_domain(Ledgr.Domains.VolumeStudio), do: Ledgr.Repos.VolumeStudio
  def repo_for_domain(Ledgr.Domains.LedgrHQ), do: Ledgr.Repos.LedgrHQ
  def repo_for_domain(Ledgr.Domains.CasaTame), do: Ledgr.Repos.CasaTame
  def repo_for_domain(_), do: Ledgr.Repos.MrMunchMe

  @doc "Returns all configured repo modules."
  def all_repos do
    [Ledgr.Repos.MrMunchMe, Ledgr.Repos.Viaxe, Ledgr.Repos.VolumeStudio, Ledgr.Repos.LedgrHQ, Ledgr.Repos.CasaTame]
  end

  # ── Ecto.Repo delegations ──────────────────────────────────────────

  # Query
  def all(queryable, opts \\ []), do: active_repo().all(queryable, opts)
  def one(queryable, opts \\ []), do: active_repo().one(queryable, opts)
  def one!(queryable, opts \\ []), do: active_repo().one!(queryable, opts)
  def aggregate(queryable, aggregate, opts \\ []), do: active_repo().aggregate(queryable, aggregate, opts)
  def aggregate(queryable, aggregate, field, opts), do: active_repo().aggregate(queryable, aggregate, field, opts)
  def exists?(queryable, opts \\ []), do: active_repo().exists?(queryable, opts)
  def stream(queryable, opts \\ []), do: active_repo().stream(queryable, opts)

  # Get
  def get(queryable, id, opts \\ []), do: active_repo().get(queryable, id, opts)
  def get!(queryable, id, opts \\ []), do: active_repo().get!(queryable, id, opts)
  def get_by(queryable, clauses, opts \\ []), do: active_repo().get_by(queryable, clauses, opts)
  def get_by!(queryable, clauses, opts \\ []), do: active_repo().get_by!(queryable, clauses, opts)

  # Insert
  def insert(struct_or_changeset, opts \\ []), do: active_repo().insert(struct_or_changeset, opts)
  def insert!(struct_or_changeset, opts \\ []), do: active_repo().insert!(struct_or_changeset, opts)
  def insert_all(schema_or_source, entries, opts \\ []), do: active_repo().insert_all(schema_or_source, entries, opts)
  def insert_or_update(changeset, opts \\ []), do: active_repo().insert_or_update(changeset, opts)
  def insert_or_update!(changeset, opts \\ []), do: active_repo().insert_or_update!(changeset, opts)

  # Update
  def update(changeset, opts \\ []), do: active_repo().update(changeset, opts)
  def update!(changeset, opts \\ []), do: active_repo().update!(changeset, opts)
  def update_all(queryable, updates, opts \\ []), do: active_repo().update_all(queryable, updates, opts)

  # Delete
  def delete(struct_or_changeset, opts \\ []), do: active_repo().delete(struct_or_changeset, opts)
  def delete!(struct_or_changeset, opts \\ []), do: active_repo().delete!(struct_or_changeset, opts)
  def delete_all(queryable, opts \\ []), do: active_repo().delete_all(queryable, opts)

  # Preload / Reload
  def preload(struct_or_structs, preloads, opts \\ []), do: active_repo().preload(struct_or_structs, preloads, opts)
  def reload(struct_or_structs, opts \\ []), do: active_repo().reload(struct_or_structs, opts)
  def reload!(struct_or_structs, opts \\ []), do: active_repo().reload!(struct_or_structs, opts)

  # Transaction
  def transaction(fun_or_multi, opts \\ []), do: active_repo().transaction(fun_or_multi, opts)
  def rollback(value), do: active_repo().rollback(value)
  def in_transaction?, do: active_repo().in_transaction?()

  # Config / Meta
  def config, do: active_repo().config()
  def __adapter__, do: active_repo().__adapter__()
end
