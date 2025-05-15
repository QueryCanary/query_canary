defmodule QueryCanary.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      QueryCanaryWeb.Telemetry,
      QueryCanary.Repo,
      {DNSCluster, query: Application.get_env(:query_canary, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: QueryCanary.PubSub},
      # Start a worker by calling: QueryCanary.Worker.start_link(arg)
      # {QueryCanary.Worker, arg},
      # Start to serve requests, typically the last entry
      QueryCanaryWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: QueryCanary.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    QueryCanaryWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
