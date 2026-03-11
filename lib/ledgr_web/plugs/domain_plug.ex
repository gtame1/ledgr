defmodule LedgrWeb.Plugs.DomainPlug do
  @moduledoc """
  Plug that sets the active domain and repo based on the request hostname or URL path prefix.

  Detection order:
  1. Hostname match — checked against `Application.get_env(:ledgr, :domain_hosts, %{})`,
     a map of `"hostname" => "slug"` pairs configured in runtime.exs for production.
  2. Path prefix — reads the slug from `/app/<slug>/...` or `/<slug>/...` (dev/localhost).

  Sets:
  - `Process.put(:ledgr_active_domain, domain_module)` for `Ledgr.Domain.current()`
  - `Process.put(:ledgr_repo, repo_module)` for `Ledgr.Repo` delegation
  - `conn.assigns[:current_domain]` for use in templates
  - `conn.assigns[:domain_path_prefix]` for building domain-scoped paths
  """

  import Plug.Conn

  @domain_slugs %{
    "mr-munch-me" => Ledgr.Domains.MrMunchMe,
    "viaxe" => Ledgr.Domains.Viaxe,
    "volume-studio" => Ledgr.Domains.VolumeStudio
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    host_slug = conn.host |> String.downcase() |> resolve_host_slug()

    if host_slug do
      conn
      |> assign(:domain_from_host, true)
      |> set_domain_context(host_slug)
    else
      case conn.path_info do
        ["app", slug | _rest] ->
          set_domain_context(conn, slug)

        # Public storefront routes: /<domain-slug>/menu/...
        [slug | _rest] ->
          case Map.get(@domain_slugs, slug) do
            nil -> conn
            _domain_module -> set_domain_context(conn, slug)
          end

        _ ->
          conn
      end
    end
  end

  defp resolve_host_slug(host) do
    hosts = Application.get_env(:ledgr, :domain_hosts, %{})
    # Try exact match first, then strip leading "www." for bare-domain entries
    Map.get(hosts, host) || Map.get(hosts, String.replace_prefix(host, "www.", ""))
  end

  defp set_domain_context(conn, slug) do
    case Map.get(@domain_slugs, slug) do
      nil ->
        conn

      domain_module ->
        repo = Ledgr.Repo.repo_for_domain(domain_module)

        # Set process dictionary for dynamic dispatch
        Ledgr.Domain.put_current(domain_module)
        Ledgr.Repo.put_active_repo(repo)

        # Set conn assigns for templates
        conn
        |> assign(:current_domain, domain_module)
        |> assign(:domain_path_prefix, domain_module.path_prefix())
    end
  end
end
