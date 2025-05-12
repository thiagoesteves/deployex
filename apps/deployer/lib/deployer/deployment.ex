defmodule Deployer.Deployment do
  @moduledoc """
  A GenServer responsible for managing deployments when a new version is available in the `current.json` file.
  It ensures deployments occur sequentially and prevents new deployments while a previous one is still in progress.

  ## Architecture
  This module follows a specific architecture for deployment management. It translates the expected behavior
  for the Deployment server.

  ![Deployment Architecture](guides/static/deployment_architecture.png)

  ## Usage
  To start the server, use `Deployer.Deployment.start_link/1` with appropriate options.
  """

  use GenServer
  require Logger

  alias Deployer.Monitor
  alias Deployer.Release
  alias Deployer.Status
  alias Deployer.Upgrade
  alias Foundation.Catalog
  alias Foundation.Common

  defstruct replicas: 1,
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

    Logger.info("Initializing Deployment Server")

    schedule_new_deployment(schedule_interval)

    initial_port = Catalog.monitored_app_start_port()
    name = Catalog.monitored_app_name()
    language = Catalog.monitored_app_lang()

    deployments =
      Catalog.replicas_list()
      |> Enum.with_index(fn instance, index -> {instance, index + initial_port} end)
      |> Enum.reduce(%{}, fn {instance, port}, acc ->
        Map.put(acc, instance, %{
          state: :init,
          timer_ref: nil,
          node: nil,
          name: name,
          port: port,
          language: language
        })
      end)

    {:ok,
     %__MODULE__{
       replicas: Catalog.replicas(),
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

  def handle_info({:timeout_rollback, instance, node}, state) do
    current_deployment = state.deployments[state.current]

    state =
      if instance == state.current and node == current_deployment.node do
        Logger.warning("The instance: #{instance} is not stable, rolling back version")

        Monitor.stop_service(state.deployments[state.current].node)

        rollback_to_previous_version(state)
      else
        # Ignore because the expiration is not for the current deployment
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:application_running, node}, %__MODULE__{} = state) do
    current_deployment = state.deployments[state.current]

    state =
      if node == current_deployment.node do
        Process.cancel_timer(current_deployment.timer_ref)

        new_instance =
          if state.current == state.replicas, do: 1, else: state.current + 1

        Logger.info(" # Moving to the next instance: #{new_instance}")

        %{state | current: new_instance}
      else
        Logger.warning(
          "Received node: #{node} that doesn't match the expected one: #{state.current} node: #{current_deployment.node}"
        )

        state
      end

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public API
  ### ==========================================================================

  @doc """
  Notifies the server that a specific application node is now running.

  ## Examples

      iex> Deployer.Deployment.notify_application_running(node)
      :ok
  """
  @spec notify_application_running(atom(), node()) :: :ok
  def notify_application_running(name \\ __MODULE__, node) do
    GenServer.cast(name, {:application_running, node})
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp schedule_new_deployment(timeout), do: Process.send_after(self(), :schedule, timeout)

  defp rollback_to_previous_version(%{current: current} = state) do
    node = state.deployments[current].node

    # Add current version to the ghosted version list
    {:ok, new_list} =
      current
      |> Status.current_version_map()
      |> Status.add_ghosted_version()

    state = %{state | ghosted_version_list: new_list}

    # Retrieve previous version
    previous_version_map = Status.history_version_list(current) |> Enum.at(1)

    deploy_application = fn ->
      case Release.download_and_unpack(node, previous_version_map.version) do
        {:ok, _} ->
          full_deployment(state, node, previous_version_map)

        reason ->
          Logger.error(
            "Error while rolling back node: #{node} to previous version, reason: #{inspect(reason)}"
          )

          state
      end
    end

    if previous_version_map != nil do
      deploy_application.()
    else
      Logger.warning(
        "Rollback requested for node: #{node} is not possible, no previous version available"
      )

      state
    end
  end

  defp initialize_version(state) do
    current_app_version = Status.current_version(state.current)

    if current_app_version != nil do
      port = state.deployments[state.current].port
      node = state.deployments[state.current].node
      language = state.deployments[state.current].language

      {:ok, _} = Monitor.start_service(node, language, port)

      set_timeout_to_rollback(state, node)
    else
      state
    end
  end

  defp check_deployment(%{current: current, ghosted_version_list: ghosted_version_list} = state) do
    node = state.deployments[current].node
    %{version: version, pre_commands: pre_commands} = release = Release.get_current_version_map()
    running_version = Status.current_version(node) || "<no current set>"

    ghosted_version? = Enum.any?(ghosted_version_list, &(&1.version == version))

    deploy_application = fn ->
      name = state.deployments[current].name
      new_node = new_node(name)

      case Release.download_and_unpack(new_node, version) do
        {:ok, :full_deployment} ->
          full_deployment(state, new_node, release)

        {:ok, :hot_upgrade} ->
          # To run the migrations for the hot upgrade deployment, deployex relies on the
          # unpacked version in the new-folder
          Monitor.run_pre_commands(new_node, pre_commands, :new)

          hot_upgrade(state, new_node, release)
      end
    end

    if version != nil and version != running_version and not ghosted_version? do
      Logger.info("Update is needed at node: #{node} from: #{running_version} to: #{version}")

      deploy_application.()
    else
      state
    end
  end

  defp set_timeout_to_rollback(%{deployments: deployments} = state, node) do
    current_deployment = state.deployments[state.current]

    timer_ref =
      Process.send_after(
        self(),
        {:timeout_rollback, state.current, node},
        state.timeout_rollback,
        []
      )

    deployments =
      Map.put(deployments, state.current, %{
        current_deployment
        | timer_ref: timer_ref,
          node: node
      })

    %{state | deployments: deployments}
  end

  defp full_deployment(%{current: instance} = state, new_node, release) do
    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      Logger.info("Full deploy instance: #{instance} node: #{new_node}")

      Monitor.stop_service(state.deployments[instance].node)

      # NOTE: Since killing the is pretty fast this delay will be enough to
      #       avoid race conditions for resources since they use the same name, ports, etc.
      :timer.sleep(Application.fetch_env!(:deployer, __MODULE__)[:delay_between_deploys_ms])

      Status.update(new_node)

      Status.set_current_version_map(new_node, release, deployment: :full_deployment)

      port = state.deployments[state.current].port
      language = state.deployments[state.current].language

      {:ok, _} = Monitor.start_service(new_node, language, port)
    end)

    set_timeout_to_rollback(state, new_node)
  end

  defp hot_upgrade(%{current: instance} = state, new_node, release) do
    # For hot code reloading, the previous deployment code is not changed
    node = state.deployments[instance].node
    language = state.deployments[instance].language
    name = state.deployments[instance].name

    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      Logger.info("Hot upgrade instance: #{instance} node: #{node}")

      from_version = Status.current_version(node)

      case Upgrade.execute(node, name, language, from_version, release.version) do
        :ok ->
          Status.set_current_version_map(node, release, deployment: :hot_upgrade)

          notify_application_running(node)
          :ok

        _reason ->
          :ok
      end
    end)

    if Status.current_version(node) != release.version do
      Logger.error("Hot Upgrade failed, running for full deployment")

      full_deployment(state, new_node, release)
    else
      state
    end
  end

  def new_node(name) do
    {:ok, hostname} = :inet.gethostname()
    reference = Common.random_small_alphanum()

    node = :"#{name}-#{reference}@#{hostname}"
    # Setup Logs
    Catalog.setup(node)

    node
  end
end
