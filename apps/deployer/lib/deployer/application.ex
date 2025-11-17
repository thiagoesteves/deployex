defmodule Deployer.Application do
  @moduledoc false

  use Application

  import Foundation.Macros

  require Logger

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Deployer.PubSub},
        Deployer.Monitor.Supervisor,
        Deployer.Engine.Supervisor,
        {Finch, name: Deployer.Finch},
        {Finch, name: ExAws.Request.Finch},
        Deployer.Github
      ] ++ application_servers() ++ gcp_app_credentials()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Deployer.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = response ->
        Deployer.Monitor.initialize_monitor_supervisor()
        init_deployment_workers()
        response

      {:error, reason} = response ->
        Logger.error("Error Initializing Deployer Supervisor reason: #{inspect(reason)}")
        response
    end
  end

  if_not_test do
    alias Deployer.Engine

    defp application_servers, do: [Deployer.Status.Application]

    defp init_deployment_workers, do: Engine.init_deployment_workers()
  else
    defp application_servers, do: []

    defp init_deployment_workers, do: :ok
  end

  defp gcp_app_credentials do
    case Application.get_env(:goth, :file_credentials) do
      nil ->
        []

      file_credentials ->
        decoded_credentials =
          file_credentials
          |> File.read!()
          |> Jason.decode!()

        [{Goth, name: Deployer.Goth, source: {:service_account, decoded_credentials}}]
    end
  end
end
