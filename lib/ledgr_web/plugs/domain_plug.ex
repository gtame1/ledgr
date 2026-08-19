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

  require Logger

  @domain_slugs %{
    "mr-munch-me" => Ledgr.Domains.MrMunchMe,
    "volume-studio" => Ledgr.Domains.VolumeStudio,
    "casa-tame" => Ledgr.Domains.CasaTame,
    "hello-doctor" => Ledgr.Domains.HelloDoctor,
    "aumenta-mi-pension" => Ledgr.Domains.AumentaMiPension,
    "escuela-de-dinero" => Ledgr.Domains.EscuelaDeDinero
  }

  @doc "Every routable slug → domain module. Exposed so tests can pin the wiring."
  def domain_slugs, do: @domain_slugs

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

        if Ledgr.Repo.started?(repo) do
          # Set process dictionary for dynamic dispatch
          Ledgr.Domain.put_current(domain_module)
          Ledgr.Repo.put_active_repo(repo)

          # Set conn assigns for templates
          conn
          |> assign(:current_domain, domain_module)
          |> assign(:domain_path_prefix, domain_module.path_prefix())
        else
          repo_not_started(conn, domain_module, repo)
        end
    end
  end

  # A domain whose repo never started (URL env var unset, or its host did not
  # resolve at boot — see Ledgr.Application) would otherwise raise "could not
  # lookup Ecto repo" on the first query, i.e. a 500 with a stacktrace on every
  # page including login. Fail with a 503 that names the missing env var instead.
  defp repo_not_started(conn, domain_module, repo) do
    Logger.error(
      "[DomainPlug] #{inspect(repo)} is not started — #{conn.method} #{conn.request_path} " <>
        "cannot be served. Set #{Ledgr.Repo.env_var_for(repo) || "its database URL"} and redeploy " <>
        "(on Render a restart reuses the deploy's environment and will not pick it up)."
    )

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(503, """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><title>Service unavailable</title></head>
    <body style="font-family: system-ui, sans-serif; max-width: 32rem; margin: 20vh auto; padding: 0 1rem;">
      <h1 style="font-size: 1.25rem;">#{domain_module.name()} is temporarily unavailable</h1>
      <p style="color: #555;">Its database is not configured on this server. An administrator needs to set the database URL and restart the app.</p>
    </body></html>
    """)
    |> halt()
  end
end
