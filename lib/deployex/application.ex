defmodule Deployex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Deployex.Macros

  @impl true
  def start(_type, _args) do
    Deployex.Storage.init()

    children =
      [
        DeployexWeb.Telemetry,
        Deployex.Monitor.Supervisor,
        {DNSCluster, query: Application.get_env(:deployex, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Deployex.PubSub},
        # Start the Finch HTTP client for sending emails
        {Finch, name: Deployex.Finch},
        # Start a worker by calling: Deployex.Worker.start_link(arg)
        # {Deployex.Worker, arg},
        # Start to serve requests, typically the last entry
        DeployexWeb.Endpoint,
        Deployex.Terminal.Supervisor
      ] ++ application_servers()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Deployex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # NOTE: Skip starting the development and status server when running tests.
  if_not_test do
    alias Deployex.Deployment

    defp application_servers do
      [
        Deployex.Status.Application,
        {Deployment,
         [
           timeout_rollback: Application.fetch_env!(:deployex, Deployment)[:timeout_rollback],
           schedule_interval: Application.fetch_env!(:deployex, Deployment)[:schedule_interval],
           name: Deployment
         ]}
      ]
    end
  else
    defp application_servers, do: []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DeployexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
