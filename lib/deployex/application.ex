defmodule Deployex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Deployex.Macros

  @impl true
  def start(_type, _args) do
    children =
      [
        DeployexWeb.Telemetry,
        Deployex.Storage.Local,
        Deployex.Monitor.Supervisor,
        Deployex.Terminal.Supervisor,
        {DNSCluster, query: Application.get_env(:deployex, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Deployex.PubSub},
        {Finch, name: Deployex.Finch},
        {Finch, name: ExAws.Request.Finch},
        {Deployex.Logs.Server, logs_config()}
      ] ++
        application_servers() ++
        gcp_app_credentials() ++
        [
          # Start a worker by calling: Deployex.Worker.start_link(arg)
          # {Deployex.Worker, arg},
          # Start to serve requests, typically the last entry
          DeployexWeb.Endpoint
        ]

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
        Deployex.System.Server,
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

  defp gcp_app_credentials do
    case Application.get_env(:goth, :file_credentials) do
      nil ->
        []

      file_credentials ->
        source = {:service_account, Jason.decode!(file_credentials)}

        [{Goth, name: Deployex.Goth, source: source}]
    end
  end

  defp logs_config, do: Application.fetch_env!(:deployex, Deployex.Logs)

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DeployexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
