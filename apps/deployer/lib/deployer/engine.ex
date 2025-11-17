defmodule Deployer.Engine do
  @moduledoc false

  require Logger

  alias Deployer.Engine
  alias Deployer.Status
  alias Foundation.Catalog
  alias Foundation.Yaml.Application, as: YamlApplication

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================
  @doc """
  Initialize deployment worker based on the passed application
  """
  @spec init_worker(application :: map()) :: :ok
  def init_worker(%YamlApplication{} = application) do
    application |> Map.from_struct() |> init_worker()
  end

  def init_worker(%{name: name} = application) do
    ghosted_version_list = Status.ghosted_version_list(name)

    service =
      struct(
        %Engine.Worker{ghosted_version_list: ghosted_version_list},
        application
      )

    Engine.Supervisor.start_deployment(service)

    :ok
  end

  @doc """
  Initialize all deployment supervisor based on the applications config
  """
  @spec init_all_workers() :: :ok
  def init_all_workers do
    Enum.each(Catalog.applications(), &init_worker/1)
    :ok
  end

  @doc """
  Notifies the deployment engine that the respective sname is running
  """
  @spec notify_application_running(sname :: String.t()) :: :ok
  def notify_application_running(sname), do: Engine.Worker.notify_application_running(sname)

  @doc """
  Force the deployment restart, which will redeploy nodes for the application.
  """
  @spec restart_deployments(name :: String.t()) :: :ok
  def restart_deployments(name), do: Engine.Worker.restart_deployments(name)
end
