defmodule Deployex.Deployment do
  @moduledoc """
  GenServer to trigger the deployment when a new version is available in the current.json
  file. It also executes the deployment in sequence, avoiding a new deployment if the
  previous was not completed yet.
  """

  @deployment_schedule_interval_ms 5_000

  use GenServer
  require Logger

  alias Deployex.{AppStatus, Monitor, Storage, Upgrade}

  @wait_time_from_stop_ms 500

  defstruct instances: 1,
            current: 1

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(instances: instances) do
    Logger.info("Initialising deployment server")
    schedule_new_deployment()
    {:ok, %__MODULE__{instances: instances}}
  end

  @impl true
  def handle_info(:schedule, state) do
    schedule_new_deployment()

    check_deployment(state.current)

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:application_running, instance},
        %__MODULE__{instances: instances, current: current} = state
      )
      when current == instance do
    schedule_new_deployment()

    new_current =
      if current == instances, do: 1, else: current + 1

    check_deployment(state.current)

    {:noreply, %{state | current: new_current}}
  end

  ### ==========================================================================
  ### Public API
  ### ==========================================================================

  @spec notify_application_running(integer()) :: :ok
  def notify_application_running(instance) do
    GenServer.cast(__MODULE__, {:application_running, instance})
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp schedule_new_deployment,
    do: Process.send_after(self(), :schedule, @deployment_schedule_interval_ms)

  defp check_deployment(instance) do
    storage = Storage.get_current_version_map()
    current_app_version = AppStatus.current_version(instance) || "<no current set>"

    if storage != nil and storage["version"] != current_app_version do
      Logger.info(
        "Update is needed at instance: #{instance} from: #{current_app_version} to: #{storage["version"]}."
      )

      case Storage.download_and_unpack(instance, storage["version"]) do
        {:ok, :full_deployment} ->
          full_deployment(instance, storage)

        {:ok, :hot_upgrade} ->
          hot_upgrade(instance, storage)
      end
    end

    :ok
  end

  defp full_deployment(instance, storage) do
    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      Monitor.stop_service(instance)

      # NOTE: Since killing the is pretty fast this delay will be enough to
      #       avoid race conditions for resources since they use the same name, ports, etc.
      :timer.sleep(@wait_time_from_stop_ms)

      AppStatus.update(instance)

      AppStatus.set_current_version_map(instance, storage, :full_deployment)

      :ok = Monitor.start_service(instance)
    end)
  end

  defp hot_upgrade(instance, storage) do
    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      from_version = AppStatus.current_version(instance)

      if :ok == Upgrade.run(instance, from_version, storage["version"]) do
        AppStatus.set_current_version_map(instance, storage, :hot_upgrade)
        notify_application_running(instance)
      end
    end)

    if AppStatus.current_version(instance) != storage["version"] do
      Logger.error("Hot Upgrade failed, running for full deployment")
      full_deployment(instance, storage)
    end
  end
end
