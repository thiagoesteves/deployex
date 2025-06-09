defmodule Deployer.Engine.Worker do
  @moduledoc """
  A GenServer responsible for managing deployments when a new version is available in the `current.json` file.
  It ensures deployments occur sequentially and prevents new deployments while a previous one is still in progress.

  ## Architecture
  This module follows a specific architecture for deployment management. It translates the expected behavior
  for the Deployment server.

  ![Deployment Architecture](guides/static/deployment_architecture.png)

  ## Usage
  To start the server, use `Deployer.Engine.start_link/1` with appropriate options.
  """

  use GenServer
  require Logger

  alias Deployer.Engine
  alias Deployer.Monitor
  alias Deployer.Release
  alias Deployer.Status
  alias Deployer.Upgrade
  alias Foundation.Catalog

  @type t :: %__MODULE__{
          replicas: non_neg_integer(),
          current: non_neg_integer(),
          name: String.t(),
          language: String.t(),
          env: list(),
          initial_port: non_neg_integer(),
          ghosted_version_list: list(),
          deployments: map(),
          timeout_rollback: non_neg_integer(),
          schedule_interval: non_neg_integer()
        }

  defstruct replicas: 1,
            current: 1,
            name: "",
            language: "",
            env: [],
            initial_port: 0,
            ghosted_version_list: [],
            deployments: %{},
            timeout_rollback: 0,
            schedule_interval: 0

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  def start_link(%__MODULE__{name: name} = deployment) do
    GenServer.start_link(__MODULE__, deployment, name: String.to_atom(name))
  end

  @impl true
  def init(
        %__MODULE__{
          name: name,
          initial_port: initial_port,
          replicas: replicas,
          schedule_interval: schedule_interval
        } = state
      ) do
    Logger.info("Initializing Engine Server for #{name}")

    schedule_new_deployment(schedule_interval)

    check_installled_apps = fn
      [] ->
        []

      installed_snames ->
        current_version =
          case Enum.at(Status.history_version_list(name, []), 0) do
            %Catalog.Version{version: version} -> version
            _ -> nil
          end

        # NOTE: Check all installed versions that are using the current version
        #       and cleanup the snames that are not in the current version
        Enum.reduce(installed_snames, [], fn sname, acc ->
          with true <- current_version == Status.current_version(sname),
               bin_path when bin_path != nil <- Catalog.bin_path(sname, :current) do
            acc ++ [sname]
          else
            _ ->
              Catalog.cleanup(sname)
              acc
          end
        end)
    end

    snames = check_installled_apps.(Status.list_installed_apps(name))

    deployments =
      1..replicas
      |> Enum.with_index(fn instance, index ->
        {instance, initial_port + index, Enum.at(snames, index)}
      end)
      |> Enum.reduce(%{}, fn {instance, port, sname}, acc ->
        Map.put(acc, instance, %Engine.Deployment{sname: sname, port: port})
      end)

    {:ok, %{state | deployments: deployments}}
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

  def handle_info({:timeout_rollback, instance, sname}, %{name: name} = state) do
    current_deployment = state.deployments[state.current]

    state =
      if instance == state.current and sname == current_deployment.sname do
        Logger.warning("The instance: #{instance} is not stable, rolling back version")

        Monitor.stop_service(name, state.deployments[state.current].sname)

        rollback_to_previous_version(state)
      else
        # Ignore because the expiration is not for the current deployment
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:application_running, sname}, %__MODULE__{} = state) do
    current_deployment = state.deployments[state.current]

    state =
      if sname == current_deployment.sname do
        Process.cancel_timer(current_deployment.timer_ref)

        new_instance =
          if state.current == state.replicas, do: 1, else: state.current + 1

        Logger.info(" # Moving to the next instance: #{new_instance}")

        %{state | current: new_instance}
      else
        Logger.warning(
          "Received sname: #{sname} that doesn't match the expected one: #{state.current} sname: #{current_deployment.sname}"
        )

        state
      end

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public API
  ### ==========================================================================

  @doc """
  Notifies the server that a specific application sname is now running.

  ## Examples

      iex> Deployer.Engine.notify_application_running(sname)
      :ok
  """
  @spec notify_application_running(String.t()) :: :ok
  def notify_application_running(sname) do
    case Catalog.node_info(sname) do
      %{name: name} ->
        name
        |> String.to_existing_atom()
        |> GenServer.cast({:application_running, sname})

      _ ->
        :ok
    end
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp schedule_new_deployment(timeout), do: Process.send_after(self(), :schedule, timeout)

  defp rollback_to_previous_version(%{current: current, name: name} = state) do
    current_sname = state.deployments[current].sname

    # Add current version to the ghosted version list
    {:ok, new_list} =
      current_sname
      |> Status.current_version_map()
      |> Status.add_ghosted_version()

    state = %{state | ghosted_version_list: new_list}

    # Retrieve previous version
    previous_version_map = Status.history_version_list(name, []) |> Enum.at(1)

    new_sname = new_sname(name)

    deploy_application = fn ->
      release_info = %Deployer.Release{
        new_sname: new_sname,
        new_sname_new_path: Catalog.new_path(new_sname),
        release_version: previous_version_map.version
      }

      case Release.download_and_unpack(release_info) do
        {:ok, _} ->
          full_deployment(state, new_sname, previous_version_map)

        {:error, _reason} ->
          state
      end
    end

    if previous_version_map != nil do
      deploy_application.()
    else
      Logger.warning(
        "Rollback requested for sname: #{current_sname} is not possible, no previous version available"
      )

      state
    end
  end

  defp initialize_version(%{language: language, current: current, name: name, env: env} = state) do
    sname = state.deployments[current].sname
    port = state.deployments[current].port
    current_version = Status.current_version(sname)

    if sname != nil and current_version != nil do
      {:ok, _} =
        Monitor.start_service(%Monitor.Service{
          name: name,
          sname: sname,
          language: language,
          port: port,
          env: env
        })

      set_timeout_to_rollback(state, sname)
    else
      state
    end
  end

  # credo:disable-for-lines:1
  defp check_deployment(
         %{current: current, ghosted_version_list: ghosted_version_list, name: name} = state
       ) do
    current_sname = state.deployments[current].sname
    current_version = current_sname && Status.current_version(current_sname)

    %{version: release_version, pre_commands: pre_commands} =
      release = Release.get_current_version_map(name)

    ghosted_version? = Enum.any?(ghosted_version_list, &(&1.version == release_version))

    deploy_application = fn ->
      new_sname = new_sname(name)

      release_info = %Deployer.Release{
        current_sname: current_sname,
        current_sname_current_path: Catalog.current_path(current_sname),
        current_sname_new_path: Catalog.new_path(current_sname),
        new_sname: new_sname,
        new_sname_new_path: Catalog.new_path(new_sname),
        current_version: current_version,
        release_version: release_version
      }

      case Release.download_and_unpack(release_info) do
        {:ok, :full_deployment} ->
          full_deployment(state, new_sname, release)

        {:ok, :hot_upgrade} ->
          # To run the migrations for the hot upgrade deployment, deployex relies on the
          # unpacked version in the new-folder
          Monitor.run_pre_commands(current_sname, pre_commands, :new)

          hot_upgrade(state, new_sname, release)

        {:error, _reason} ->
          state
      end
    end

    cond do
      is_nil(current_version) and is_nil(release_version) ->
        Logger.warning("No versions set yet for #{name}")
        state

      release_version != nil and release_version != current_version and not ghosted_version? ->
        version = current_version || "<no current set>"

        Logger.info(
          "Update is needed at sname: #{current_sname} from: #{version} to: #{release_version}"
        )

        deploy_application.()

      true ->
        state
    end
  end

  defp set_timeout_to_rollback(%{deployments: deployments} = state, sname) do
    current_deployment = state.deployments[state.current]

    timer_ref =
      Process.send_after(
        self(),
        {:timeout_rollback, state.current, sname},
        state.timeout_rollback,
        []
      )

    deployments =
      Map.put(deployments, state.current, %{
        current_deployment
        | timer_ref: timer_ref,
          sname: sname
      })

    %{state | deployments: deployments}
  end

  defp full_deployment(
         %{current: instance, language: language, name: name, env: env} = state,
         new_sname,
         release
       ) do
    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      Logger.info("Full deploy instance: #{instance} sname: #{new_sname}")

      sname = state.deployments[instance].sname

      Monitor.stop_service(name, sname)

      # NOTE: Since killing the is pretty fast this delay will be enough to
      #       avoid race conditions for resources since they use the same name, ports, etc.
      :timer.sleep(Application.fetch_env!(:deployer, Engine)[:delay_between_deploys_ms])

      Status.update(new_sname)

      Status.set_current_version_map(new_sname, release, deployment: :full_deployment)

      port = state.deployments[state.current].port

      {:ok, _} =
        Monitor.start_service(%Monitor.Service{
          name: name,
          sname: new_sname,
          language: language,
          port: port,
          env: env
        })

      Catalog.cleanup(sname)
    end)

    set_timeout_to_rollback(state, new_sname)
  end

  defp hot_upgrade(
         %{current: instance, name: name, language: language} = state,
         new_sname,
         release
       ) do
    # For hot code reloading, the previous deployment code is not changed
    sname = state.deployments[instance].sname

    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      Logger.info("Hot upgrade instance: #{instance} sname: #{sname}")

      from_version = Status.current_version(sname)

      %{node: node} = Catalog.node_info(sname)

      upgrade_data = %Deployer.Upgrade.Execute{
        node: node,
        sname: sname,
        name: name,
        language: language,
        current_path: Catalog.current_path(sname),
        new_path: Catalog.new_path(sname),
        from_version: from_version,
        to_version: release.version
      }

      case Upgrade.execute(upgrade_data) do
        :ok ->
          Status.set_current_version_map(sname, release, deployment: :hot_upgrade)

          # Cleanup Any folder left for the new sname
          Catalog.cleanup(new_sname)

          notify_application_running(sname)
          :ok

        _reason ->
          :ok
      end
    end)

    if Status.current_version(sname) != release.version do
      Logger.error("Hot Upgrade failed, running for full deployment")

      full_deployment(state, new_sname, release)
    else
      state
    end
  end

  def new_sname(name) do
    sname = Catalog.create_sname(name)

    # Setup Logs and folders
    Catalog.setup(sname)

    sname
  end
end
