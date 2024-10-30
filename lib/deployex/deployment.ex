defmodule Deployex.Deployment do
  @moduledoc """
  A GenServer responsible for managing deployments when a new version is available in the `current.json` file.
  It ensures deployments occur sequentially and prevents new deployments while a previous one is still in progress.

  ## Architecture
  This module follows a specific architecture for deployment management. It translates the expected behavior
  for the Deployment server.

  ![Deployment Architecture](docs/static/deployment_architecture.png)

  ## Usage
  To start the server, use `Deployex.Deployment.start_link/1` with appropriate options.
  """

  use GenServer
  require Logger

  alias Deployex.Common
  alias Deployex.Monitor
  alias Deployex.Release
  alias Deployex.Status
  alias Deployex.Storage
  alias Deployex.Upgrade

  defstruct instances: 1,
            current: 1,
            ghosted_version_list: [],
            deployments: %{},
            timeout_rollback: 0,
            schedule_interval: 0

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  def start_link(args) do
    name = Keyword.fetch!(args, :name)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    timeout_rollback = Keyword.fetch!(args, :timeout_rollback)
    schedule_interval = Keyword.fetch!(args, :schedule_interval)

    Logger.info("Initialising deployment server")

    schedule_new_deployment(schedule_interval)

    deployments =
      Storage.replicas_list()
      |> Enum.reduce(%{}, fn instance, acc ->
        Map.put(acc, instance, %{state: :init, timer_ref: nil, deploy_ref: nil})
      end)

    {:ok,
     %__MODULE__{
       instances: Storage.replicas(),
       deployments: deployments,
       timeout_rollback: timeout_rollback,
       schedule_interval: schedule_interval,
       ghosted_version_list: Status.ghosted_version_list()
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

    state =
      if instance == state.current and
           deploy_ref == current_deployment.deploy_ref do
        Process.cancel_timer(current_deployment.timer_ref)

        new_current =
          if state.current == state.instances, do: 1, else: state.current + 1

        Logger.info(" # Moving to the next instance: #{new_current}")

        %{state | current: new_current}
      else
        Logger.warning(
          "Received instance: #{instance} deploy_ref: #{deploy_ref} that doesn't match the expected one: #{state.current} deploy_ref: #{current_deployment.deploy_ref}"
        )

        state
      end

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public API
  ### ==========================================================================

  @doc """
  Notifies the server that a specific application instance is now running.

  ## Examples

      iex> Deployex.Deployment.notify_application_running(instance, deploy_ref)
      :ok
  """
  @spec notify_application_running(integer(), String.t()) :: :ok
  def notify_application_running(name \\ __MODULE__, instance, deploy_ref) do
    GenServer.cast(name, {:application_running, instance, deploy_ref})
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp schedule_new_deployment(timeout), do: Process.send_after(self(), :schedule, timeout)

  defp rollback_to_previous_version(%{current: instance} = state) do
    # Add current version to the ghosted version list
    {:ok, new_list} =
      state.current
      |> Status.current_version_map()
      |> Status.add_ghosted_version()

    state = %{state | ghosted_version_list: new_list}

    # Retrieve previous version
    previous_version_map = Status.history_version_list(instance) |> Enum.at(1)

    deploy_application = fn ->
      case Release.download_and_unpack(instance, previous_version_map.version) do
        {:ok, _} ->
          full_deployment(state, previous_version_map)

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
    current_app_version = Status.current_version(state.current)
    new_deploy_ref = Common.random_small_alphanum()

    if current_app_version != nil do
      {:ok, _} =
        Monitor.start_service(Storage.monitored_app_lang(), state.current, new_deploy_ref)

      set_timeout_to_rollback(state, new_deploy_ref)
    else
      state
    end
  end

  defp check_deployment(%{current: instance, ghosted_version_list: ghosted_version_list} = state) do
    release = Release.get_current_version_map()
    current_app_version = Status.current_version(instance) || "<no current set>"

    ghosted_version? = Enum.any?(ghosted_version_list, &(&1.version == release.version))

    deploy_application = fn ->
      case Release.download_and_unpack(instance, release.version) do
        {:ok, :full_deployment} ->
          full_deployment(state, release)

        {:ok, :hot_upgrade} ->
          # To run the migrations for the hot upgrade deployment, deployex relies on the
          # unpacked version in the new-folder
          Monitor.run_pre_commands(instance, release.pre_commands, :new)
          hot_upgrade(state, release)
      end
    end

    if release.version != nil and release.version != current_app_version and not ghosted_version? do
      log_message =
        "Update is needed at instance: #{instance} from: #{current_app_version} to: #{release.version}"

      Logger.info(log_message)

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

  defp full_deployment(%{current: instance} = state, release) do
    new_deploy_ref = Common.random_small_alphanum()

    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      log_message =
        "Full deploy instance: #{instance} deploy_ref: #{new_deploy_ref}"

      Logger.info(log_message)

      Monitor.stop_service(instance)

      # NOTE: Since killing the is pretty fast this delay will be enough to
      #       avoid race conditions for resources since they use the same name, ports, etc.
      :timer.sleep(Application.fetch_env!(:deployex, __MODULE__)[:delay_between_deploys_ms])

      Status.update(instance)

      Status.set_current_version_map(instance, release,
        deployment: :full_deployment,
        deploy_ref: new_deploy_ref
      )

      {:ok, _} = Monitor.start_service(Storage.monitored_app_lang(), instance, new_deploy_ref)
    end)

    set_timeout_to_rollback(state, new_deploy_ref)
  end

  defp hot_upgrade(%{current: instance} = state, release) do
    # For hot code reloading, the previous deployment code is not changed
    deploy_ref = state.deployments[instance].deploy_ref

    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      log_message =
        "Hot upgrade instance: #{instance} deploy_ref: #{deploy_ref}"

      Logger.info(log_message)

      from_version = Status.current_version(instance)

      case Upgrade.execute(
             instance,
             Storage.monitored_app_lang(),
             Storage.monitored_app_name(),
             from_version,
             release.version
           ) do
        :ok ->
          Status.set_current_version_map(instance, release,
            deployment: :hot_upgrade,
            deploy_ref: deploy_ref
          )

          notify_application_running(instance, deploy_ref)
          :ok

        _reason ->
          :ok
      end
    end)

    if Status.current_version(instance) != release.version do
      Logger.error("Hot Upgrade failed, running for full deployment")

      full_deployment(state, release)
    else
      state
    end
  end
end
