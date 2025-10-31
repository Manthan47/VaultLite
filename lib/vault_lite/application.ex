defmodule VaultLite.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      VaultLiteWeb.Telemetry,
      VaultLite.Repo,
      {DNSCluster, query: Application.get_env(:vault_lite, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: VaultLite.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: VaultLite.Finch},
      # Enhanced rate limiting cache
      %{
        id: :rate_limit_cache_supervisor,
        start:
          {Task, :start_link,
           [
             fn ->
               :ets.new(:rate_limit_cache, [:named_table, :public, :set])
               Process.sleep(:infinity)
             end
           ]}
      },
      # Security monitoring
      VaultLite.Security.Monitor,
      # Start a worker by calling: VaultLite.Worker.start_link(arg)
      # {VaultLite.Worker, arg},
      # Start to serve requests, typically the last entry
      VaultLiteWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VaultLite.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configurationr
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    VaultLiteWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
