defmodule Deployex.Deployment do
  @moduledoc """
  GenServer to trigger the deployment when it is required.
  """

  @schedule_interval_ms 5_000

  use GenServer
  require Logger

  alias Deployex.{State, Storage, Upgrade}

  @wait_time_from_stop_ms 500

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg)
  end

  @impl true
  def init(_arg) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:schedule, state) do
    state = run_check(state)
    schedule_check()
    {:noreply, state}
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp schedule_check, do: Process.send_after(self(), :schedule, @schedule_interval_ms)

  defp run_check(state) do
    storage = Storage.get_current_version_map()
    current_app_version = State.current_version() || "<no current set>"

    if storage != nil and storage["version"] != current_app_version do
      Logger.info("Update is needed from #{current_app_version} to #{storage["version"]}.")

      case Storage.download_and_unpack(storage["version"]) do
        {:ok, :full_deployment} ->
          full_deployment(storage)

        {:ok, :hot_upgrade} ->
          hot_upgrade(storage)
      end
    else
      state
    end
  end

  defp full_deployment(storage) do
    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      Deployex.Monitor.stop_service()

      # NOTE: Since killing the is pretty fast this delay will be enough to
      #       avoid race conditions for resources since they use the same name, ports, etc.
      :timer.sleep(@wait_time_from_stop_ms)

      State.update()

      State.set_current_version_map(storage)

      :ok = Deployex.Monitor.start_service()
    end)
  end

  defp hot_upgrade(storage) do
    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      from_version = State.current_version()

      if :ok == Upgrade.run(from_version, storage["version"]) do
        State.set_current_version_map(storage)
      end
    end)

    if State.current_version() != storage["version"] do
      Logger.error("Hot Upgrade failed, running for full deployment")
      full_deployment(storage)
    end
  end
end
