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
        {DNSCluster, query: Application.get_env(:deployex, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Deployex.PubSub},
        # Start the Finch HTTP client for sending emails
        {Finch, name: Deployex.Finch}
      ] ++
        application_servers() ++
        gcp_app_credentials() ++
        [
          # Start a worker by calling: Deployex.Worker.start_link(arg)
          # {Deployex.Worker, arg},
          # Start to serve requests, typically the last entry
          DeployexWeb.Endpoint,
          Deployex.Terminal.Supervisor
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
    secrets_gcp_adapter? =
      Application.get_env(:deployex, Deployex.ConfigProvider.Secrets.Manager)[:adapter] ==
        Deployex.ConfigProvider.Secrets.Gcp

    release_gcp_adapter? =
      Application.get_env(:deployex, Deployex.Release)[:adapter] ==
        Deployex.Release.GcpStorage

    if secrets_gcp_adapter? or release_gcp_adapter? do
      credentials =
        "GOOGLE_APPLICATION_CREDENTIALS"
        |> System.fetch_env!()
        |> File.read!()
        |> Jason.decode!()

      source = {:service_account, credentials}

      [{Goth, name: Deployex.Goth, source: source}]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DeployexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
