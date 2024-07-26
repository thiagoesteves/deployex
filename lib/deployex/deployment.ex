defmodule Deployex.Deployment do
  @moduledoc """
  GenServer to trigger the deployment when a new version is available in the current.json
  file. It also executes the deployment in sequence, avoiding a new deployment if the
  previous was not completed yet.
  """

  @wait_time_from_stop_ms 500

  use GenServer
  require Logger

  alias Deployex.{AppStatus, Common, Monitor, Storage, Upgrade}

  defstruct instances: 1,
            current: 1,
            ghosted_version_list: [],
            deployments: %{},
            timeout_rollback: 0,
            schedule_interval: 0

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(instances: instances) do
    Logger.info("Initialising deployment server")
    timeout_rollback = Application.fetch_env!(:deployex, __MODULE__)[:timeout_rollback]
    schedule_interval = Application.fetch_env!(:deployex, __MODULE__)[:schedule_interval]

    schedule_new_deployment(schedule_interval)

    deployments =
      Enum.to_list(1..instances)
      |> Enum.reduce(%{}, fn instance, acc ->
        Map.put(acc, instance, %{state: :init, timer_ref: nil, deploy_ref: nil})
      end)

    {:ok,
     %__MODULE__{
       instances: instances,
       deployments: deployments,
       timeout_rollback: timeout_rollback,
       schedule_interval: schedule_interval,
       ghosted_version_list: AppStatus.ghosted_version_list()
     }}
  end

  @impl true
  def handle_info(:schedule, %__MODULE__{} = state) do
    schedule_new_deployment(state.schedule_interval)
    current_deployment = state.deployments[state.current]

    new_state =
      if current_deployment.state == :init do
        state = initialize_version(state)

        deployments =
          Map.put(state.deployments, state.current, %{
            state.deployments[state.current]
            | state: :active
          })

        %{state | deployments: deployments}
      else
        check_deployment(state)
      end

    {:noreply, new_state}
  end

  def handle_info({:timeout_rollback, instance, deploy_ref}, state) do
    current_deployment = state.deployments[state.current]

    state =
      if instance == state.current and deploy_ref == current_deployment.deploy_ref do
        Logger.warning("The instance: #{instance} is not stable, rolling back version")

        Monitor.stop_service(state.current)

        rollback_to_previous_version(state)
      else
        # Ignore because the expiration is not for the current deployment
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:application_running, instance, deploy_ref}, %__MODULE__{} = state) do
    current_deployment = state.deployments[state.current]
    updated_deployment = state.deployments[instance]

    state =
      cond do
        instance == state.current and deploy_ref == current_deployment.deploy_ref ->
          Process.cancel_timer(current_deployment.timer_ref)

          new_current =
            if state.current == state.instances, do: 1, else: state.current + 1

          Logger.info(" # Moving to the next instance: #{new_current}")

          %{state | current: new_current}

        instance != state.current and deploy_ref == updated_deployment.deploy_ref ->
          # Ignore because the application restarted and it is now runnitn again
          state

        true ->
          Logger.error(
            "Received instance: #{instance} deploy_ref: #{Common.short_ref(deploy_ref)} that doesn't match the expected one: #{state.current} deploy_ref: #{Common.short_ref(current_deployment.deploy_ref)}"
          )

          state
      end

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public API
  ### ==========================================================================

  @spec notify_application_running(integer(), reference()) :: :ok
  def notify_application_running(instance, deploy_ref) do
    GenServer.cast(__MODULE__, {:application_running, instance, deploy_ref})
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp schedule_new_deployment(timeout), do: Process.send_after(self(), :schedule, timeout)

  defp rollback_to_previous_version(%{current: instance} = state) do
    # Add current version to the ghosted version list
    {:ok, new_list} =
      state.current
      |> AppStatus.current_version_map()
      |> AppStatus.add_ghosted_version_list()

    state = %{state | ghosted_version_list: new_list}

    previous_version_map = AppStatus.previous_version_map(instance)

    deploy_application = fn ->
      deploy_ref = :erlang.make_ref()

      case Storage.download_and_unpack(instance, previous_version_map["version"]) do
        {:ok, _} ->
          full_deployment(state, previous_version_map, deploy_ref)

        reason ->
          Logger.error(
            "Error while rolling back instance: #{instance} to previous version, reason: #{inspect(reason)}"
          )

          state
      end
    end

    if previous_version_map != nil do
      deploy_application.()
    else
      Logger.warning(
        "Rollback requested for instance: #{instance} is not possible, no previous version available"
      )

      state
    end
  end

  defp initialize_version(state) do
    current_app_version = AppStatus.current_version(state.current)
    deploy_ref = :erlang.make_ref()

    if current_app_version != nil do
      :ok = Monitor.start_service(state.current, deploy_ref)
      set_timeout_to_rollback(state, deploy_ref)
    else
      state
    end
  end

  defp check_deployment(%{current: instance, ghosted_version_list: ghosted_version_list} = state) do
    storage = Storage.get_current_version_map()
    current_app_version = AppStatus.current_version(instance) || "<no current set>"

    ghosted_version? = Enum.any?(ghosted_version_list, &(&1["version"] == storage["version"]))

    deploy_application = fn ->
      deploy_ref = :erlang.make_ref()

      case Storage.download_and_unpack(instance, storage["version"]) do
        {:ok, :full_deployment} ->
          full_deployment(state, storage, deploy_ref)

        {:ok, :hot_upgrade} ->
          hot_upgrade(state, storage, deploy_ref)
      end
    end

    if storage != nil and storage["version"] != current_app_version and not ghosted_version? do
      Logger.info(
        "Update is needed at instance: #{instance} from: #{current_app_version} to: #{storage["version"]}."
      )

      deploy_application.()
    else
      state
    end
  end

  defp set_timeout_to_rollback(%{deployments: deployments} = state, deploy_ref) do
    current_deployment = state.deployments[state.current]

    timer_ref =
      Process.send_after(
        self(),
        {:timeout_rollback, state.current, deploy_ref},
        state.timeout_rollback,
        []
      )

    deployments =
      Map.put(deployments, state.current, %{
        current_deployment
        | timer_ref: timer_ref,
          deploy_ref: deploy_ref
      })

    %{state | deployments: deployments}
  end

  defp full_deployment(%{current: instance} = state, storage, deploy_ref) do
    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      Logger.info(
        "Full deploy instance: #{instance} deploy_ref: #{Common.short_ref(deploy_ref)}."
      )

      Monitor.stop_service(instance)

      # NOTE: Since killing the is pretty fast this delay will be enough to
      #       avoid race conditions for resources since they use the same name, ports, etc.
      :timer.sleep(@wait_time_from_stop_ms)

      AppStatus.update(instance)

      AppStatus.set_current_version_map(instance, storage,
        deployment: :full_deployment,
        deploy_ref: deploy_ref
      )

      :ok = Monitor.start_service(instance, deploy_ref)
    end)

    set_timeout_to_rollback(state, deploy_ref)
  end

  defp hot_upgrade(%{current: instance} = state, storage, deploy_ref) do
    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      Logger.info(
        "Hot upgrade instance: #{instance} deploy_ref: #{Common.short_ref(deploy_ref)}."
      )

      from_version = AppStatus.current_version(instance)

      if :ok == Upgrade.run(instance, from_version, storage["version"]) do
        AppStatus.set_current_version_map(instance, storage,
          deployment: :hot_upgrad,
          deploy_ref: deploy_ref
        )

        notify_application_running(instance, deploy_ref)
      end
    end)

    if AppStatus.current_version(instance) != storage["version"] do
      Logger.error("Hot Upgrade failed, running for full deployment")

      full_deployment(state, storage, deploy_ref)
    else
      state
    end
  end
end
