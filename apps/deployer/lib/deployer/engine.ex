defmodule Deployer.Engine do
  @moduledoc false

  require Logger

  alias Deployer.Engine
  alias Deployer.Status
  alias Foundation.Catalog

  ### ==========================================================================
  ### Public APIs
  ### ==========================================================================
  @spec init_deployment_workers() :: :ok
  def init_deployment_workers do
    Enum.each(Catalog.applications(), fn %{name: name} = application ->
      ghosted_version_list = Status.ghosted_version_list(name)

      service =
        struct(
          %Engine.Worker{ghosted_version_list: ghosted_version_list},
          application
        )

      {:ok, _pid} = Engine.Supervisor.start_deployment(service)
    end)

    :ok
  end

  @doc """
  Notifies the deployment engine that the respective sname is running
  """
  @spec notify_application_running(String.t()) :: :ok
  def notify_application_running(sname), do: Engine.Worker.notify_application_running(sname)
end
