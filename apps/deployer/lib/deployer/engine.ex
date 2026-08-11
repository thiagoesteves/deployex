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

  @doc """
  Retrieve the ghosted version list for the application
  """
  @spec ghosted_version_list(name :: String.t()) :: list()
  def ghosted_version_list(name), do: Status.ghosted_version_list(name)

  @doc """
  Remove one version from the ghosted version list, allowing it to be deployed again
  """
  @spec remove_ghosted_version(name :: String.t(), version :: String.t()) :: {:ok, list()}
  def remove_ghosted_version(name, version) do
    call_worker(name, {:remove_ghosted_version, version}, fn ->
      Status.remove_ghosted_version(name, version)
    end)
  end

  @doc """
  Remove every version from the ghosted version list
  """
  @spec clear_ghosted_versions(name :: String.t()) :: {:ok, list()}
  def clear_ghosted_versions(name) do
    call_worker(name, :clear_ghosted_versions, fn -> Status.clear_ghosted_versions(name) end)
  end

  # The worker keeps its own copy of the ghosted list and consults it on every deployment
  # check, so the change has to go through it while it is running, otherwise it would keep
  # skipping a version that is no longer ghosted. With no worker there is no copy to keep in
  # step and the stored list is the only thing to update
  defp call_worker(name, message, without_worker) do
    case Process.whereis(String.to_existing_atom(name)) do
      nil -> without_worker.()
      pid -> GenServer.call(pid, message)
    end
  end
end
