defmodule Deployex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Deployex.Configuration.init(replicas_list())

    children =
      [
        Deployex.Deployment.Supervisor,
        Deployex.Monitor.Supervisor,
        DeployexWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:deployex, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Deployex.PubSub},
        # Start the Finch HTTP client for sending emails
        {Finch, name: Deployex.Finch},
        # Start a worker by calling: Deployex.Worker.start_link(arg)
        # {Deployex.Worker, arg},
        # Start to serve requests, typically the last entry
        DeployexWeb.Endpoint,
        {Deployex.AppStatus, instances: replicas()}
      ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Deployex.Supervisor]
    response = Supervisor.start_link(children, opts)

    # Initialise instances
    replicas_list()
    |> Enum.each(&Deployex.Monitor.Supervisor.new(instance: &1))

    replicas_list()
    |> Enum.each(&Deployex.Deployment.Supervisor.new(instance: &1))

    response
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DeployexWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp replicas, do: Application.get_env(:deployex, :replicas)
  defp replicas_list, do: Enum.to_list(1..replicas())
end
