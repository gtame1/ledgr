defmodule Ledgr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  # Mix is not available at runtime in compiled releases; capture the env at
  # compile time so the dev-only branch is evaluated as a constant.
  @mix_env Mix.env()

  @impl true
  def start(_type, _args) do
    # Inject dev-only endpoint config (watchers, live_reload) at runtime so
    # config files stay serializable and Mix can read them (e.g. mix release).
    if @mix_env == :dev do
      endpoint_config = Application.get_env(:ledgr, LedgrWeb.Endpoint) || []
      watchers = [
        esbuild: {Esbuild, :install_and_run, [:ledgr, ~w(--sourcemap=inline --watch)]},
        tailwind: {Tailwind, :install_and_run, [:ledgr, ~w(--watch)]}
      ]
      live_reload = [
        web_console_logger: true,
        patterns: [
          ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
          ~r"priv/gettext/.*(po)$",
          ~r"lib/ledgr_web/(?:controllers|live|components|router)/?.*\.(ex|heex)$"
        ]
      ]
      Application.put_env(:ledgr, LedgrWeb.Endpoint,
        Keyword.merge(endpoint_config, watchers: watchers, live_reload: live_reload)
      )
    end

    children = [
      LedgrWeb.Telemetry,
      Ledgr.Repos.MrMunchMe,
      Ledgr.Repos.Viaxe,
      Ledgr.Repos.VolumeStudio,
      {DNSCluster, query: Application.get_env(:ledgr, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ledgr.PubSub},
      # Start to serve requests, typically the last entry
      LedgrWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ledgr.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LedgrWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
