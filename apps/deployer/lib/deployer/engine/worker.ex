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
  alias Deployer.HotUpgrade
  alias Deployer.Monitor
  alias Deployer.Release
  alias Deployer.Status
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
          deploy_schedule_interval_ms: non_neg_integer(),
          pending_pre_commands: map() | nil
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
            deploy_schedule_interval_ms: 0,
            pending_pre_commands: nil

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

    # A restart after a relup gets the start argument the old code built, without this field
    state = Map.put_new(state, :pending_pre_commands, nil)

    # Subscribe before reading, in this order. A change made in between then arrives as a
    # message instead of being lost in the gap. Reading here is also what makes a restarted
    # worker current, the supervisor hands back the list captured when it was first started
    Status.subscribe_ghosted_versions(name)
    ghosted_version_list = Status.ghosted_version_list(name)

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

    {deployments, available_ports} = build_deployments(replica_ports, replicas, snames)

    {:ok,
     %{
       state
       | deployments: deployments,
         ghosted_version_list: ghosted_version_list,
         available_ports: available_ports
     }}
  end

  @impl true
  def handle_info(:schedule, %__MODULE__{} = state) do
    # A worker that a relup could not suspend kept a state without this field
    state = Map.put_new(state, :pending_pre_commands, nil)
    schedule_new_deployment(state.deploy_schedule_interval_ms)
    current_deployment = state.deployments[state.current]

    new_state =
      cond do
        current_deployment.state == :init ->
          # initialize_version can move current to the next instance
          instance = state.current
          state = initialize_version(state)

          deployments =
            Map.put(state.deployments, instance, %{
              state.deployments[instance]
              | state: :active
            })

          %{state | deployments: deployments}

        # A hot upgrade is waiting for its pre_commands, the reply decides what happens next
        state.pending_pre_commands != nil ->
          state

        true ->
          check_deployment(state)
      end

    {:noreply, new_state}
  end

  def handle_info(
        {:pre_commands_result, ref, result},
        %__MODULE__{pending_pre_commands: %{ref: ref} = pending} = state
      ) do
    {:noreply, pre_commands_outcome(state, pending, result)}
  end

  # The monitor took the request, so a timeout from now on means the pre_commands ran too long.
  # The timer starts again here, so time spent on busy replies does not shorten the run
  def handle_info(
        {:pre_commands_started, ref},
        %__MODULE__{pending_pre_commands: %{ref: ref, id: id} = pending} = state
      ) do
    Process.cancel_timer(pending.timer_ref)

    receive do
      {:pre_commands_timeout, ^id} -> :ok
    after
      0 -> :ok
    end

    timer_ref = Process.send_after(self(), {:pre_commands_timeout, id}, pending.timeout)
    pending = Map.merge(pending, %{started: true, timer_ref: timer_ref})

    {:noreply, %{state | pending_pre_commands: pending}}
  end

  def handle_info(
        {:pre_commands_timeout, id},
        %__MODULE__{pending_pre_commands: %{id: id} = pending} = state
      ) do
    {:noreply, pre_commands_outcome(state, pending, :timeout)}
  end

  def handle_info(
        {:pre_commands_retry, id},
        %__MODULE__{pending_pre_commands: %{id: id} = pending} = state
      ) do
    {:noreply, retry_pre_commands(state, pending)}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %__MODULE__{pending_pre_commands: %{ref: ref} = pending} = state
      ) do
    {:noreply, pre_commands_outcome(state, pending, {:monitor_exit, reason})}
  end

  # A reply, a timeout or a retry for a request that is no longer pending
  def handle_info({:pre_commands_started, _ref}, state), do: {:noreply, state}
  def handle_info({:pre_commands_result, _ref, _result}, state), do: {:noreply, state}
  def handle_info({:pre_commands_timeout, _id}, state), do: {:noreply, state}
  def handle_info({:pre_commands_retry, _id}, state), do: {:noreply, state}

  # A monitor ref that code of the previous version set up and dropped during a relup
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  # Only a change on this node matters, the ghosted list is stored by the DeployEx instance
  # that owns the application
  def handle_info(
        {:ghosted_versions_updated, source_node, _name, ghosted_version_list},
        %__MODULE__{} = state
      )
      when source_node == node() do
    {:noreply, %{state | ghosted_version_list: ghosted_version_list}}
  end

  def handle_info({:ghosted_versions_updated, _source_node, _name, _list}, state) do
    {:noreply, state}
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

        # Return deployment to the current one. When the rollback timer was
        # armed by the initial boot there is no previous deployment to return
        # to, so reset the instance to an empty deployment
        deployments =
          Map.put(deployments, state.current, deployment_to_terminate || %Engine.Deployment{})

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
  def handle_cast(:restart_deployments, %__MODULE__{} = state) do
    {:noreply, state |> abandon_pending_pre_commands() |> do_restart_deployments()}
  end

  def handle_cast(
        {:updated_state_values, %{replicas: new_replicas}},
        %__MODULE__{replicas: current_replicas} = state
      )
      when new_replicas > current_replicas do
    Logger.warning("Adding new replicas for #{state.name}")

    # The new replica becomes current, so a pending request ends here like on a restart
    state = abandon_pending_pre_commands(state)

    # Check the available port between the old set and the new set.
    all_ports =
      Enum.with_index(0..new_replicas, fn _instance, index ->
        Enum.shuffle(build_ports_by_index(state.replica_ports, index))
      end)

    used_ports =
      Enum.map(state.deployments, fn {_instance, %Engine.Deployment{ports: ports}} -> ports end) ++
        [state.available_ports]

    available_ports =
      MapSet.difference(
        MapSet.new(all_ports, &Enum.sort_by(&1, fn m -> m.key end)),
        MapSet.new(used_ports, &Enum.sort_by(&1, fn m -> m.key end))
      )
      |> MapSet.to_list()

    next_instance = current_replicas + 1

    {new_deployments, _available_ports} =
      Enum.reduce(
        next_instance..new_replicas,
        {state.deployments, available_ports},
        fn instance, {deployments, available_ports} ->
          case available_ports do
            [ports | rest] ->
              {Map.put(deployments, instance, %Engine.Deployment{ports: ports}), rest}

            _ ->
              {Map.put(deployments, instance, %Engine.Deployment{ports: []}), []}
          end
        end
      )

    {:noreply,
     %{
       state
       | deployments: new_deployments,
         replicas: new_replicas,
         current: next_instance
     }}
  end

  def handle_cast(
        {:updated_state_values, %{replicas: new_replicas}},
        %__MODULE__{replicas: current_replicas} = state
      ) do
    Logger.warning("Removing replicas for #{state.name}")

    state =
      case Map.get(state, :pending_pre_commands) do
        %{instance: instance} when instance > new_replicas -> abandon_pending_pre_commands(state)
        _pending -> state
      end

    new_deployments =
      Enum.reduce(1..current_replicas, state.deployments, fn instance, deployments ->
        if instance <= new_replicas do
          deployments
        else
          %{sname: sname} = deployments[instance]
          Logger.info(" # Terminating node: #{sname}")
          Monitor.stop_service(state.name, sname)
          Catalog.cleanup(sname)
          Map.delete(deployments, instance)
        end
      end)

    # A request that stays keeps its instance current, so its outcome still counts
    current =
      case Map.get(state, :pending_pre_commands) do
        %{instance: instance} -> instance
        nil -> 1
      end

    {:noreply,
     %{
       state
       | deployments: new_deployments,
         replicas: new_replicas,
         current: current
     }}
  end

  def handle_cast({:updated_state_values, %{replica_ports: replica_ports}}, %__MODULE__{} = state) do
    Logger.warning("Updating replica ports for #{state.name}")

    {:noreply,
     state
     |> abandon_pending_pre_commands()
     |> Map.put(:replica_ports, replica_ports)
     |> do_restart_deployments()}
  end

  def handle_cast({:updated_state_values, values}, %__MODULE__{} = state) do
    {:noreply, struct(state, values)}
  end

  def handle_cast(
        {:application_running, sname},
        %__MODULE__{deployment_to_terminate: deployment_to_terminate} = state
      ) do
    current_deployment = state.deployments[state.current]

    state =
      if sname == current_deployment.sname do
        # NOTE: The rollback timer may not be armed, e.g. when the monitor
        #       reports running right after an engine worker restart
        if current_deployment.timer_ref, do: Process.cancel_timer(current_deployment.timer_ref)

        # deploying? is set where a version is put into service, by a full deployment and by
        # the start up path, so it is what says this report completes one. Everything else
        # that reports running, a crash restart, a restart asked for from the UI, or a hot
        # upgrade that has already reported itself with the versions it moved between,
        # finds it false and is not announced as a deployment
        if current_deployment.deploying?, do: notify_deployment_complete(sname)

        # Whatever put the application there, it is running and the system has qualified it
        # as ready, which is the report itself. A crash restart and a restart asked for
        # from the UI reach here too, and this is the event that says so
        notify_application_ready(sname)

        # An app that comes back while its hot upgrade waits for it keeps the instance current,
        # so the upgrade goes on there
        new_instance =
          cond do
            match?(%{sname: ^sname}, Map.get(state, :pending_pre_commands)) -> state.current
            state.current == state.replicas -> 1
            true -> state.current + 1
          end

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

        # This report closed the window: the timer was cancelled above and the flag goes
        # with it, so a later report for the same deployment, e.g. after a crash restart,
        # is not taken for another one
        deployments =
          Map.put(state.deployments, state.current, %{
            current_deployment
            | timer_ref: nil,
              deploying?: false
          })

        %{
          state
          | current: new_instance,
            deployments: deployments,
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

  # A state from a version without pending_pre_commands gets the field on a relup
  @impl true
  def code_change(_old_vsn, state, _extra),
    do: {:ok, Map.put_new(state, :pending_pre_commands, nil)}

  ### ==========================================================================
  ### Public API
  ### ==========================================================================

  @doc """
  Notifies the server that a specific application sname is now running.

  ## Examples

      iex> Deployer.Engine.notify_application_running(sname)
      :ok
  """
  @spec notify_application_running(sname :: String.t()) :: :ok
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

  @doc """
  Update application state values that are upgradable. All values MUST be updated individually

  - language
  - env
  - deploy_rollback_timeout_ms
  - deploy_schedule_interval_ms
  - replica_ports
  - replicas

  ## Examples

      iex> Deployer.Engine.updated_state_values("myapp", %{language: language})
      :ok
  """
  @spec updated_state_values(name :: String.t(), values :: map()) :: :ok
  def updated_state_values(name, values) do
    name
    |> String.to_existing_atom()
    |> GenServer.cast({:updated_state_values, values})
  end

  @doc """
  Force the deployment restart, which will redeploy nodes for the application.

  ## Examples

      iex> Deployer.Engine.Worker.restart_deployments("myapp")
      :ok
  """
  @spec restart_deployments(name :: String.t()) :: :ok
  def restart_deployments(name) do
    name
    |> String.to_existing_atom()
    |> GenServer.cast(:restart_deployments)
  end

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================

  defp schedule_new_deployment(timeout), do: Process.send_after(self(), :schedule, timeout)

  defp build_ports_by_index(replica_ports, index) do
    Enum.map(replica_ports, fn port -> %{port | base: port.base + index} end)
  end

  # A monitor that outlived an engine worker restart keeps the ports it runs the app on, which
  # full deployments rotate. The other instances and the spare set take the sets nobody holds
  defp build_deployments(replica_ports, replicas, snames) do
    held_ports = Enum.map(snames, &monitor_ports/1)
    held = held_ports |> Enum.reject(&is_nil/1) |> MapSet.new(&sort_ports/1)

    free_ports =
      0..replicas
      |> Enum.map(&build_ports_by_index(replica_ports, &1))
      |> Enum.reject(&MapSet.member?(held, sort_ports(&1)))

    {deployments, free_ports} =
      Enum.reduce(1..replicas, {%{}, free_ports}, fn instance, {deployments, free_ports} ->
        {ports, free_ports} =
          case Enum.at(held_ports, instance - 1) do
            nil -> take_ports(free_ports)
            ports -> {ports, free_ports}
          end

        deployment = %Engine.Deployment{sname: Enum.at(snames, instance - 1), ports: ports}
        {Map.put(deployments, instance, deployment), free_ports}
      end)

    {available_ports, _free_ports} = take_ports(free_ports)
    {deployments, available_ports}
  end

  defp monitor_ports(sname) do
    case Monitor.state(sname) do
      %Monitor{sname: ^sname, ports: ports} -> ports
      _state -> nil
    end
  end

  defp take_ports([ports | rest]), do: {ports, rest}
  defp take_ports([]), do: {[], []}

  defp sort_ports(ports), do: Enum.sort_by(ports, & &1.key)

  defp do_restart_deployments(
         %__MODULE__{deployments: deployments, replica_ports: replica_ports, replicas: replicas} =
           state
       ) do
    new_deployments =
      Enum.reduce(deployments, %{}, fn {instance, %Engine.Deployment{sname: sname}}, acc ->
        Logger.info(" # Terminating node: #{sname}")
        Foundation.Notifications.notify("deployment_shutdown", %{node: node(), sname: sname})
        Monitor.stop_service(state.name, sname)
        Catalog.cleanup(sname)

        ports = build_ports_by_index(replica_ports, instance - 1)
        Map.put(acc, instance, %Engine.Deployment{ports: ports})
      end)

    %{
      state
      | deployments: new_deployments,
        available_ports: build_ports_by_index(replica_ports, replicas),
        deployment_to_terminate: nil
    }
  end

  defp initialize_version(%{language: language, current: current, name: name, env: env} = state) do
    sname = state.deployments[current].sname
    ports = state.deployments[current].ports
    current_version = Status.current_version(sname)

    if sname != nil and current_version != nil do
      started =
        start_monitor_service!(%Monitor.Service{
          name: name,
          sname: sname,
          language: language,
          ports: ports,
          env: env
        })

      # A monitor that already runs the app does not report it running again, so a rollback
      # window would never close and would stop the app when it expires
      if started == :already_started and app_running?(sname) do
        Logger.info(" # Application sname: #{sname} is already running")
        %{state | current: if(current == state.replicas, do: 1, else: current + 1)}
      else
        set_timeout_to_rollback(state, sname, ports)
      end
    else
      state
    end
  end

  # NOTE: The monitor may already be running when the engine worker is
  #       restarted by its supervisor, since monitors live in a separate
  #       supervision tree.
  defp start_monitor_service!(%Monitor.Service{} = service) do
    case Monitor.start_service(service) do
      {:ok, _pid} ->
        :started

      {:error, {:already_started, _pid}} ->
        Logger.warning("Monitor for sname: #{service.sname} is already running")
        :already_started
    end
  end

  defp app_running?(sname) do
    case Monitor.state(sname) do
      %Monitor{current_pid: pid, status: :running} when is_pid(pid) -> true
      _state -> false
    end
  end

  # credo:disable-for-lines:1
  defp check_deployment(
         %{current: current, ghosted_version_list: ghosted_version_list, name: name} = state
       ) do
    current_sname = state.deployments[current].sname
    current_version = current_sname && Status.current_version(current_sname)

    %{version: release_version} = release = Release.get_current_version_map(name)

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
          request_hot_upgrade_pre_commands(state, current_sname, new_sname, release)

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

  # The migrations run from the new version before install. The reply comes as a message, so a
  # long migration does not block the worker
  defp request_hot_upgrade_pre_commands(state, _sname, new_sname, %{pre_commands: []} = release),
    do: hot_upgrade(state, new_sname, release)

  defp request_hot_upgrade_pre_commands(state, sname, new_sname, release) do
    pending = %{instance: state.current, sname: sname, new_sname: new_sname, release: release}

    case Monitor.start_pre_commands(sname, release.pre_commands, :new) do
      {:ok, ref} ->
        # id stays for the whole request and keys its timers, ref changes on each retry. The
        # timeout is the value at request time, a later config change applies to the next one
        id = make_ref()
        timeout = state.deploy_rollback_timeout_ms
        timer_ref = Process.send_after(self(), {:pre_commands_timeout, id}, timeout)

        pending =
          Map.merge(pending, %{id: id, ref: ref, timer_ref: timer_ref, timeout: timeout})

        %{state | pending_pre_commands: pending}

      {:error, :not_running} ->
        monitor_gone(state, pending)
    end
  end

  # A busy monitor is asked again with the release already unpacked, within the same timeout.
  # Pre_commands that already ran are not sent again, the empty list only waits for the app
  defp retry_pre_commands(state, pending) do
    if state.deployments[state.current].sname == pending.sname do
      pre_commands = if pending[:ran], do: [], else: pending.release.pre_commands

      case Monitor.start_pre_commands(pending.sname, pre_commands, :new) do
        {:ok, ref} ->
          %{state | pending_pre_commands: Map.merge(pending, %{ref: ref, started: false})}

        {:error, :not_running} ->
          state |> clear_pending_pre_commands(pending) |> monitor_gone(pending)
      end
    else
      abandon_pending_pre_commands(state)
    end
  end

  # A busy reply keeps the request, and the same request is sent again after a schedule tick
  defp pre_commands_outcome(state, pending, {:error, :busy}) do
    Logger.warning("The monitor for sname: #{pending.sname} is busy or restarting, asking again")
    schedule_pre_commands_retry(state, pending)
  end

  # The pre_commands ran, then the app went down or restarts. The retry waits for the app
  defp pre_commands_outcome(state, pending, {:error, :app_down}) do
    Logger.warning(
      "The pre-commands at sname: #{pending.sname} ran, waiting for the app to run again"
    )

    schedule_pre_commands_retry(state, Map.put(pending, :ran, true))
  end

  # An outcome counts only while its instance is still the one being upgraded. Otherwise it is
  # dropped: a result means the command ended, and a timeout stops the command below
  defp pre_commands_outcome(state, pending, outcome) do
    if state.deployments[state.current].sname == pending.sname do
      state
      |> clear_pending_pre_commands(pending)
      |> apply_pre_commands_outcome(pending, outcome)
    else
      Logger.warning(
        "Dropping the pre-commands outcome for sname: #{pending.sname}, it is not current"
      )

      # A hung command would keep that monitor busy for every later request
      if outcome == :timeout, do: Monitor.cancel_pre_commands(pending.sname, pending.ref)

      Catalog.cleanup(pending.new_sname)
      clear_pending_pre_commands(state, pending)
    end
  end

  defp schedule_pre_commands_retry(state, pending) do
    Process.demonitor(pending.ref, [:flush])

    Process.send_after(
      self(),
      {:pre_commands_retry, pending.id},
      state.deploy_schedule_interval_ms
    )

    %{state | pending_pre_commands: pending}
  end

  # The version map can move on during a long migration, the next check deploys the new one
  defp apply_pre_commands_outcome(state, pending, {:ok, _pre_commands}) do
    if Release.get_current_version_map(state.name).version == pending.release.version do
      hot_upgrade(state, pending.new_sname, pending.release)
    else
      Logger.warning(
        "The version changed while the pre-commands ran for sname: #{pending.sname}, " <>
          "not installing #{pending.release.version}"
      )

      Catalog.cleanup(pending.new_sname)
      state
    end
  end

  # The monitor already logged which command failed
  defp apply_pre_commands_outcome(state, pending, {:error, _reason}),
    do: pre_commands_failed(state, pending)

  # The pre_commands ran but the app did not run again in time, so the release is deployed fully
  defp apply_pre_commands_outcome(state, %{ran: true} = pending, :timeout) do
    Logger.error(
      "The app at sname: #{pending.sname} did not run again within #{pending.timeout} ms " <>
        "after its pre-commands, deploying fully"
    )

    Monitor.cancel_pre_commands(pending.sname, pending.ref)
    full_deployment(state, pending.new_sname, pending.release)
  end

  defp apply_pre_commands_outcome(state, %{started: true} = pending, :timeout) do
    Logger.error(
      "Pre-commands at sname: #{pending.sname} did not finish within " <>
        "#{pending.timeout} ms, stopping them"
    )

    Monitor.cancel_pre_commands(pending.sname, pending.ref)
    pre_commands_failed(state, pending)
  end

  # The monitor never started the run, so no pre_command ran and the release is deployed fully.
  # The cancel stops a request that the monitor takes later
  defp apply_pre_commands_outcome(state, pending, :timeout) do
    Logger.error(
      "The monitor for sname: #{pending.sname} did not start the pre-commands within " <>
        "#{pending.timeout} ms, deploying fully"
    )

    Monitor.cancel_pre_commands(pending.sname, pending.ref)
    full_deployment(state, pending.new_sname, pending.release)
  end

  # The monitor was gone before the request reached it, or it exited during the run. Neither says
  # the release is bad, so it is deployed fully
  defp apply_pre_commands_outcome(state, pending, {:monitor_exit, :noproc}),
    do: monitor_gone(state, pending)

  defp apply_pre_commands_outcome(state, pending, {:monitor_exit, reason}) do
    Logger.error(
      "The monitor for sname: #{pending.sname} exited while running the pre-commands, " <>
        "reason: #{inspect(reason)}"
    )

    monitor_gone(state, pending)
  end

  # The monitor is gone or restarting, so a full deployment brings up a new supervised instance.
  # Both paths were unpacked, so the new sname is ready
  defp monitor_gone(state, %{sname: sname, new_sname: new_sname, release: release}) do
    Logger.warning("The monitor for sname: #{sname} is not running, deploying fully")
    full_deployment(state, new_sname, release)
  end

  # A restart, an added replica, or a replica change that removes the instance, ends the request
  # without a ghost
  defp abandon_pending_pre_commands(state) do
    case Map.get(state, :pending_pre_commands) do
      nil -> state
      pending -> abandon_pending_pre_commands(state, pending)
    end
  end

  defp abandon_pending_pre_commands(state, pending) do
    Logger.warning("Dropping the pre-commands request for sname: #{pending.sname}")

    Monitor.cancel_pre_commands(pending.sname, pending.ref)
    Catalog.cleanup(pending.new_sname)
    clear_pending_pre_commands(state, pending)
  end

  defp clear_pending_pre_commands(state, %{ref: ref, timer_ref: timer_ref}) do
    Process.cancel_timer(timer_ref)
    Process.demonitor(ref, [:flush])

    %{state | pending_pre_commands: nil}
  end

  # Nothing is installed yet, so the release is ghosted like any other hot upgrade that fails
  # before install
  defp pre_commands_failed(state, %{sname: sname, new_sname: new_sname, release: release}) do
    handle_hot_upgrade_result(
      {:error, {:not_installed, :pre_commands}},
      state,
      sname,
      new_sname,
      release
    )
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
          ports: ports,
          deploying?: true
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

      start_monitor_service!(%Monitor.Service{
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

    result =
      :global.trans({{__MODULE__, :deploy_lock}, self()}, fn ->
        Logger.info("Hot upgrade instance: #{instance} sname: #{sname}")

        from_version = Status.current_version(sname)

        %{node: node} = Catalog.node_info(sname)

        upgrade_data = %Deployer.HotUpgrade.Execute{
          node: node,
          sname: sname,
          name: name,
          language: language,
          current_path: Catalog.current_path(sname),
          new_path: Catalog.new_path(sname),
          from_version: from_version,
          to_version: release.version
        }

        case HotUpgrade.execute(upgrade_data) do
          :ok ->
            Status.set_current_version_map(sname, release, deployment: :hot_upgrade)

            # Cleanup Any folder left for the new sname
            Catalog.cleanup(new_sname)

            notify_application_running(sname)
            :ok

          error ->
            error
        end
      end)

    handle_hot_upgrade_result(result, state, sname, new_sname, release)
  end

  defp notify_application_ready(sname) do
    Foundation.Notifications.notify("application_ready", %{
      node: node(),
      sname: sname,
      version: to_string(Status.current_version(sname))
    })
  end

  # The deployment wrote the version to the catalog before the sname reported running, so
  # the notification reads it from there instead of threading it through the call
  defp notify_deployment_complete(sname) do
    version = Status.current_version(sname)

    Foundation.Notifications.notify("deployment_complete", %{
      node: node(),
      sname: sname,
      status: :ok,
      message: "Full deployment applied successfully, version #{version}",
      version: to_string(version)
    })
  end

  # The release said it could hot upgrade, through its appup or jellyfish file, otherwise
  # this deployment would never have reached here. It then failed without the node having
  # been touched, so there is nothing to recover and no reason to restart it. Ghost the
  # version so the engine stops offering it and the application keeps serving what it runs
  defp handle_hot_upgrade_result(
         {:error, {:not_installed, reason}},
         %{name: name} = state,
         sname,
         new_sname,
         release
       ) do
    Logger.error(
      "Hot upgrade failed before the release was installed at sname: #{sname}, " <>
        "reason: #{inspect(reason)}. #{name} is still running " <>
        "#{Status.current_version(sname)}, ghosting version #{release.version}."
    )

    # Nothing was installed, so the folders prepared for the new sname are unused
    Catalog.cleanup(new_sname)

    {:ok, ghosted_version_list} =
      Status.add_ghosted_version(%Catalog.Version{
        version: release.version,
        hash: release.hash,
        pre_commands: release.pre_commands,
        name: name,
        sname: sname,
        deployment: :hot_upgrade,
        inserted_at: NaiveDateTime.utc_now()
      })

    %{state | ghosted_version_list: ghosted_version_list}
  end

  defp handle_hot_upgrade_result(_result, state, sname, new_sname, release) do
    if Status.current_version(sname) != release.version do
      Logger.error("Hot Upgrade failed, running for full deployment")

      full_deployment(state, new_sname, release)
    else
      # The upgrade reported itself with the versions it moved between, and the sname it
      # ran on keeps running. A window left open on this instance, e.g. by a start up whose
      # monitor was already running, would otherwise turn the report the upgrade triggers
      # into a full deployment of this version
      current_deployment = %{state.deployments[state.current] | deploying?: false}

      %{state | deployments: Map.put(state.deployments, state.current, current_deployment)}
    end
  end

  def new_sname(name) do
    sname = Catalog.create_sname(name)

    # Setup Logs and folders
    Catalog.setup_new_node(sname)

    sname
  end
end
