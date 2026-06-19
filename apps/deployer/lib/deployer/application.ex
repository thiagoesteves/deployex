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
        Deployer.HotUpgrade.Application,
        {Finch, name: Deployer.Finch},
        {Finch, name: ExAws.Request.Finch},
        Deployer.Github.Release,
        Deployer.Github.Artifact
      ] ++ application_servers() ++ gcp_app_credentials()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Deployer.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = response ->
        Deployer.Monitor.init_all_monitor_supervisors()
        init_all_workers()
        notify_startup()
        response

      {:error, reason} = response ->
        Logger.error("Error Initializing Deployer Application reason: #{inspect(reason)}")
        response
    end
  end

  @impl true
  def stop(_state) do
    notify_shutdown()
  end

  if_not_test do
    alias Deployer.Engine

    defp application_servers, do: [Deployer.Status.Application]

    defp init_all_workers, do: Engine.init_all_workers()

    defp notify_startup do
      version = Application.spec(:deployer, :vsn) |> to_string()

      Foundation.Notifications.notify("deployment_started", %{
        node: node(),
        sname: "deployex",
        version: version
      })
    end

    defp notify_shutdown do
      Foundation.Notifications.notify("deployment_complete", %{
        node: node(),
        sname: "deployex",
        status: :ok,
        message: "shutdown"
      })
    end
  else
    defp application_servers, do: []

    defp init_all_workers, do: :ok

    defp notify_startup, do: :ok

    defp notify_shutdown, do: :ok
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
