defmodule DeployexWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DeployexWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:deployex_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DeployexWeb.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: DeployexWeb.Finch},
      # Start a worker by calling: DeployexWeb.Worker.start_link(arg)
      # {DeployexWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      DeployexWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DeployexWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DeployexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
