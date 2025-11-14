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
          replica_ports: list(),
          available_ports: list(),
          ghosted_version_list: list(),
          deployments: map(),
          deployment_to_terminate: map(),
          deploy_rollback_timeout_ms: non_neg_integer(),
          deploy_schedule_interval_ms: non_neg_integer()
        }

  defstruct replicas: 1,
            current: 1,
            name: "",
            language: "",
            env: [],
            replica_ports: [],
            available_ports: [],
            ghosted_version_list: [],
            deployments: %{},
            deployment_to_terminate: nil,
            deploy_rollback_timeout_ms: 0,
            deploy_schedule_interval_ms: 0

  @dialyzer {:nowarn_function, initialize_version: 1}

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
          replica_ports: replica_ports,
          replicas: replicas,
          deploy_schedule_interval_ms: deploy_schedule_interval_ms
        } = state
      ) do
    Logger.info("Initializing Engine Server for #{name}")

    schedule_new_deployment(deploy_schedule_interval_ms)

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

    build_ports_by_index = fn index ->
      Enum.map(replica_ports, fn port -> %{port | base: port.base + index} end)
    end

    deployments =
      1..replicas
      |> Enum.with_index(fn instance, index ->
        {instance, build_ports_by_index.(index), Enum.at(snames, index)}
      end)
      |> Enum.reduce(%{}, fn {instance, ports, sname}, acc ->
        Map.put(acc, instance, %Engine.Deployment{sname: sname, ports: ports})
      end)

    {:ok, %{state | deployments: deployments, available_ports: build_ports_by_index.(replicas)}}
  end

  @impl true
  def handle_info(:schedule, %__MODULE__{} = state) do
    schedule_new_deployment(state.deploy_schedule_interval_ms)
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

  def handle_info(
        {:timeout_rollback, instance, sname},
        %{name: name, deployments: deployments, deployment_to_terminate: deployment_to_terminate} =
          state
      ) do
    current_deployment = state.deployments[state.current]

    state =
      if instance == state.current and sname == current_deployment.sname do
        sname = current_deployment.sname
        ports = current_deployment.ports

        Logger.warning(
          "The instance: #{instance} sname: #{sname} ports: #{inspect(ports)} is not stable, ghosting version"
        )

        Monitor.stop_service(name, sname)
        Catalog.cleanup(sname)

        # Add current version to the ghosted version list
        {:ok, new_list} =
          sname
          |> Status.current_version_map()
          |> Status.add_ghosted_version()

        # Return deployment to the current one
        deployments = Map.put(deployments, state.current, deployment_to_terminate)

        %{
          state
          | deployments: deployments,
            deployment_to_terminate: nil,
            ghosted_version_list: new_list,
            available_ports: ports
        }
      else
        # Ignore because the expiration is not for the current deployment
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:application_running, sname},
        %__MODULE__{deployment_to_terminate: deployment_to_terminate} = state
      ) do
    current_deployment = state.deployments[state.current]

    state =
      if sname == current_deployment.sname do
        Process.cancel_timer(current_deployment.timer_ref)

        new_instance =
          if state.current == state.replicas, do: 1, else: state.current + 1

        available_ports =
          if deployment_to_terminate do
            Logger.info(" # Terminating previous node: #{deployment_to_terminate.sname}")
            Monitor.stop_service(state.name, deployment_to_terminate.sname)
            Catalog.cleanup(deployment_to_terminate.sname)
            deployment_to_terminate.ports
          else
            state.available_ports
          end

        Logger.info(" # Moving to the next instance: #{new_instance}")

        %{
          state
          | current: new_instance,
            deployment_to_terminate: nil,
            available_ports: available_ports
        }
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

  defp initialize_version(%{language: language, current: current, name: name, env: env} = state) do
    sname = state.deployments[current].sname
    ports = state.deployments[current].ports
    current_version = Status.current_version(sname)

    if sname != nil and current_version != nil do
      {:ok, _} =
        Monitor.start_service(%Monitor.Service{
          name: name,
          sname: sname,
          language: language,
          ports: ports,
          env: env
        })

      set_timeout_to_rollback(state, sname, ports)
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

  defp set_timeout_to_rollback(%{deployments: deployments} = state, sname, ports) do
    current_deployment = state.deployments[state.current]

    timer_ref =
      Process.send_after(
        self(),
        {:timeout_rollback, state.current, sname},
        state.deploy_rollback_timeout_ms,
        []
      )

    deployments =
      Map.put(deployments, state.current, %{
        current_deployment
        | timer_ref: timer_ref,
          sname: sname,
          ports: ports
      })

    %{state | deployments: deployments}
  end

  # NOTE: Receiving a new deployment while the previous one is still in progress
  defp full_deployment(
         %{
           name: name,
           deployments: deployments,
           deployment_to_terminate: deployment_to_terminate
         } =
           state,
         new_sname,
         release
       )
       when deployment_to_terminate != nil do
    sname = state.deployments[state.current].sname
    ports = state.deployments[state.current].ports

    Logger.info(" # Terminating node: #{sname} before receiving running state")

    Monitor.stop_service(name, sname)
    Catalog.cleanup(sname)

    # Return deployment to the current one
    deployments = Map.put(deployments, state.current, deployment_to_terminate)

    state = %{
      state
      | deployments: deployments,
        deployment_to_terminate: nil,
        available_ports: ports
    }

    full_deployment(state, new_sname, release)
  end

  defp full_deployment(
         %{
           current: instance,
           language: language,
           name: name,
           env: env,
           available_ports: available_ports
         } = state,
         new_sname,
         release
       ) do
    deployment_to_terminate = state.deployments[state.current]

    :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
      Logger.info("Full deploy instance: #{instance} sname: #{new_sname}")

      Status.update(new_sname)

      Status.set_current_version_map(new_sname, release, deployment: :full_deployment)

      {:ok, _} =
        Monitor.start_service(%Monitor.Service{
          name: name,
          sname: new_sname,
          language: language,
          ports: available_ports,
          env: env
        })
    end)

    state
    |> set_timeout_to_rollback(new_sname, available_ports)
    |> Map.put(:deployment_to_terminate, deployment_to_terminate)
    |> Map.put(:available_ports, [])
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
