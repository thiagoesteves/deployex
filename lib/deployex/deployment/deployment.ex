defmodule Deployex.Deployment do
  @moduledoc """
  GenServer to trigger the deployment when it is required.
  """

  @deployment_schedule_interval_ms 5_000

  use GenServer
  require Logger

  alias Deployex.{AppStatus, Monitor, Storage, Upgrade}

  @wait_time_from_stop_ms 500

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  @impl true
  def init(instance: instance) do
    Logger.metadata(instance: instance)

    Logger.info("Initialising Deployment for instance: #{instance}")
    schedule_new_deployment()
    {:ok, %{instance: instance}}
  end

  @impl true
  def handle_info(:schedule, state) do
    schedule_new_deployment()

    state = check_deployment(state)

    {:noreply, state}
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp schedule_new_deployment,
    do: Process.send_after(self(), :schedule, @deployment_schedule_interval_ms)

  defp check_deployment(%{instance: instance} = state) do
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
    else
      state
    end
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
      end
    end)

    if AppStatus.current_version(instance) != storage["version"] do
      Logger.error("Hot Upgrade failed, running for full deployment")
      full_deployment(instance, storage)
    end
  end
end
