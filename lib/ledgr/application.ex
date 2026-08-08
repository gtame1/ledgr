defmodule Ledgr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

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

      Application.put_env(
        :ledgr,
        LedgrWeb.Endpoint,
        Keyword.merge(endpoint_config, watchers: watchers, live_reload: live_reload)
      )
    end

    # Optional repos: in test always start all repos (they're configured in
    # config/test.exs); in dev/prod only start when their DATABASE_URL is set.
    optional_repos =
      if @mix_env != :prod do
        Enum.map(Ledgr.Repo.optional_repos(), fn {_env_var, repo} -> repo end)
      else
        Ledgr.Repo.optional_repos()
        |> Enum.filter(fn {env_var, repo} ->
          case System.get_env(env_var) do
            nil ->
              # Silence here is how a whole domain ends up 503ing in production:
              # its routes ship, its repo never starts. Say so at boot.
              Logger.warning(
                "[Ledgr] Skipping #{inspect(repo)}: #{env_var} is not set — every request for this domain will return 503"
              )

              false

            url ->
              if db_host_reachable?(url) do
                true
              else
                Logger.warning(
                  "[Ledgr] Skipping #{inspect(repo)}: #{env_var} is set but host does not resolve (database may be expired)"
                )

                false
              end
          end
        end)
        |> Enum.map(fn {_env_var, repo} -> repo end)
      end

    # Start exchange rate worker only when Casa Tame repo is available.
    # Skip in :test to avoid spurious DB connections during the test run.
    # Pull HelloDoctor external billing (OpenAI, Whereby, AWS) every 15 days
    # and post the new costs to the GL. Skip in :test.
    children =
      [
        LedgrWeb.Telemetry,
        Ledgr.Repos.MrMunchMe
      ] ++
        optional_repos ++
        [
          {DNSCluster, query: Application.get_env(:ledgr, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Ledgr.PubSub},
          Ledgr.Domains.MrMunchMe.PendingCheckoutRecovery
        ] ++
        if(@mix_env != :test and Ledgr.Repos.CasaTame in optional_repos,
          do: [Ledgr.Domains.CasaTame.ExchangeRates.ExchangeRateWorker],
          else: []
        ) ++
        if(@mix_env != :test and Ledgr.Repos.HelloDoctor in optional_repos,
          do: [
            Ledgr.Domains.HelloDoctor.BillingSyncWorker,
            Ledgr.Domains.HelloDoctor.ExchangeRateWorker,
            Ledgr.Domains.HelloDoctor.PatientSegmentsWorker,
            Ledgr.Domains.HelloDoctor.ConsultationPayoutsWorker,
            Ledgr.Domains.HelloDoctor.DailySnapshotWorker
          ],
          else: []
        ) ++
        if(@mix_env != :test and Ledgr.Repos.AumentaMiPension in optional_repos,
          do: [Ledgr.Domains.AumentaMiPension.FunnelStageAudit],
          else: []
        ) ++
        [
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

  # Returns false only on nxdomain — meaning the host genuinely doesn't exist
  # (deleted/expired database). Any other error (refused, timeout) returns true
  # so the repo still starts and Postgrex handles reconnection normally.
  defp db_host_reachable?(url) do
    host = url |> URI.parse() |> Map.get(:host)

    if is_nil(host) or host == "" do
      false
    else
      case :inet.gethostbyname(to_charlist(host)) do
        {:ok, _} -> true
        {:error, :nxdomain} -> false
        _ -> true
      end
    end
  end
end
