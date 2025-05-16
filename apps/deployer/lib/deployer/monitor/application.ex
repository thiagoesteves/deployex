defmodule Deployer.Monitor.Application do
  @moduledoc """
  GenServer that monitor and supervise the application.
  """
  use GenServer
  require Logger

  alias Deployer.Deployment
  alias Deployer.Status
  alias Foundation.Catalog
  alias Foundation.Common
  alias Host.Commander

  @behaviour Deployer.Monitor.Adapter

  @monitor_table "monitor-table"

  @default_timeout_app_ready :timer.seconds(30)
  @default_retry_delay_pre_commands :timer.seconds(1)

  @new_deploy_topic "new-deploy-topic"

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    node = Keyword.fetch!(args, :node)
    name = global_name(node)
    GenServer.start_link(__MODULE__, args, name: {:global, name})
  end

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)

    port = Keyword.fetch!(args, :port)
    node = Keyword.fetch!(args, :node)
    language = Keyword.fetch!(args, :language)
    options = Keyword.fetch!(args, :options)

    timeout_app_ready =
      Keyword.get(options, :timeout_app_ready, @default_timeout_app_ready)

    retry_delay_pre_commands =
      Keyword.get(options, :retry_delay_pre_commands, @default_retry_delay_pre_commands)

    # NOTE: This ETS table provides non-blocking access to the state.
    :ets.new(table_name(node), [:set, :protected, :named_table])

    Logger.info("Initializing monitor server for node: #{node} language: #{language}")

    trigger_run_service(node)

    {:ok,
     update_non_blocking_state(%Deployer.Monitor{
       timeout_app_ready: timeout_app_ready,
       retry_delay_pre_commands: retry_delay_pre_commands,
       node: node,
       port: port,
       language: language
     })}
  end

  @impl true
  def handle_call(
        :stop_service,
        _from,
        %Deployer.Monitor{current_pid: current_pid, node: node} = state
      )
      when is_nil(current_pid) do
    Logger.warning("Requested node: #{node} to stop but application is not running.")

    {:reply, :ok, state}
  end

  def handle_call(
        :stop_service,
        _from,
        %Deployer.Monitor{node: node, current_pid: pid} = state
      ) do
    Logger.info("Requested node: #{node} to stop application pid: #{inspect(pid)}")

    # Stop current application
    Commander.stop(state.current_pid)

    # NOTE: The next command is needed for Systems that have a different PID for the "/bin/app start" script
    #       and the bin/beam.smp process
    cleanup_beam_process(state.node)

    {:reply, :ok, state}
  end

  # This command is available during the hot upgrade. If it fails, the process will
  # restart and attempt a full deployment.
  def handle_call({:run_pre_commands, pre_commands, app_bin_service}, _from, state) do
    :ok = execute_pre_commands(state, pre_commands, app_bin_service)

    {:reply, {:ok, pre_commands}, state}
  end

  def handle_call(:restart, _from, state) when is_nil(state.current_pid) do
    {:reply, {:error, :application_is_not_running}, state}
  end

  def handle_call(:restart, _from, state) do
    Logger.warning("Restart requested for node: #{state.node}")

    # Stop current application
    Commander.stop(state.current_pid)

    cleanup_beam_process(state.node)

    # Update the number of force restarts
    force_restart_count = state.force_restart_count + 1

    # Trigger restart with backoff time of 1 second
    trigger_run_service(state.node, 1_000)

    {:reply, :ok, update_non_blocking_state(%{state | force_restart_count: force_restart_count})}
  end

  @impl true
  def handle_info({:run_service, node}, %Deployer.Monitor{} = state)
      when node == state.node do
    version_map = Status.current_version_map(state.node)
    version = version_map.version

    state =
      if version == nil do
        Logger.info("No version set, not able to run_service")
        state
      else
        Logger.info("Ensure running requested for node: #{node} version: #{version}")

        run_service(state, version_map)
      end

    {:noreply, update_non_blocking_state(state)}
  end

  def handle_info({:check_running, pid, node}, state)
      when pid == state.current_pid and node == state.node do
    Logger.info(" # Application node: #{state.node} is running")

    Deployment.notify_application_running(node)

    {:noreply, update_non_blocking_state(%{state | status: :running})}
  end

  def handle_info({:check_running, _pid, _node}, state) do
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, :normal}, state) do
    # Ignore any erl_exec application that terminates normally, as this
    # occurs because the process is trapping all exits, including those
    # that are expected.
    {:noreply, state}
  end

  def handle_info({:EXIT, pid, _reason}, %{current_pid: current_pid} = state)
      when current_pid == pid do
    Logger.error(
      "Unexpected exit message received for node: #{state.node} from pid: #{inspect(pid)}, application being restarted"
    )

    cleanup_beam_process(state.node)

    # Update the number of crash restarts
    crash_restart_count = state.crash_restart_count + 1

    # Retry with backoff pattern
    trigger_run_service(state.node, 2 * crash_restart_count * 1000)

    {:noreply, update_non_blocking_state(%{state | crash_restart_count: crash_restart_count})}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    Logger.warning(
      "Application node: #{state.node} with pid: #{inspect(pid)} being stopped by reason: #{inspect(reason)}"
    )

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================
  @impl true
  def state(node) do
    [{_, value}] =
      table_name(node)
      |> :ets.lookup(:state)

    value
  rescue
    _ ->
      %Deployer.Monitor{}
  end

  @impl true
  def run_pre_commands(node, pre_commands, app_bin_service) do
    global_name(node)
    |> Common.call_gen_server({:run_pre_commands, pre_commands, app_bin_service})
  end

  @impl true
  defdelegate start_service(node, language, port, options \\ []),
    to: Deployer.Monitor.Supervisor

  @impl true
  defdelegate stop_service(node), to: Deployer.Monitor.Supervisor

  @impl true
  defdelegate list, to: Deployer.Monitor.Supervisor

  @impl true
  def subscribe_new_deploy do
    Phoenix.PubSub.subscribe(Deployer.PubSub, @new_deploy_topic)
  end

  @impl true
  def restart(node) do
    node
    |> global_name()
    |> Common.call_gen_server(:restart)
  end

  @impl true
  def global_name(node),
    do: %{module: __MODULE__, node: node}

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  def trigger_run_service(node, timeout \\ 1),
    do: Process.send_after(self(), {:run_service, node}, timeout)

  defp run_service(
         %Deployer.Monitor{
           node: node,
           timeout_app_ready: timeout_app_ready,
           retry_delay_pre_commands: retry_delay_pre_commands,
           language: language
         } = state,
         version_map
       ) do
    app_exec = Catalog.bin_path(node, language, :current)
    version = version_map.version

    with true <- File.exists?(app_exec),
         :ok <- Logger.info(" # Identified executable: #{app_exec}"),
         :ok <- execute_pre_commands(state, version_map.pre_commands, :current) do
      Logger.info(" # Starting application")

      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        @new_deploy_topic,
        {:new_deploy, Node.self(), node}
      )

      {:ok, pid, os_pid} =
        Commander.run_link(
          run_app_bin(state, app_exec, "start"),
          [
            {:stdout, Catalog.stdout_path(node) |> to_charlist, [:append, {:mode, 0o600}]},
            {:stderr, Catalog.stderr_path(node) |> to_charlist, [:append, {:mode, 0o600}]}
          ]
        )

      Logger.info(
        " # Running node: #{node}, monitoring pid = #{inspect(pid)}, OS process = #{os_pid} node: #{node}"
      )

      Process.send_after(self(), {:check_running, pid, node}, timeout_app_ready)

      %{state | current_pid: pid, status: :starting, start_time: now()}
    else
      false ->
        trigger_run_service(node, retry_delay_pre_commands)
        Logger.error("Version: #{version} set but no #{app_exec}")
        state

      {:error, :pre_commands} ->
        trigger_run_service(node, retry_delay_pre_commands)
        %{state | status: :pre_commands}
    end
  end

  # NOTE: Some commands need to run prior starting the application
  #       - Unset env vars from the deployex release to not mix with the monitored app release
  #       - Export suffix to add different snames to the apps
  #       - Export listening port that needs to be one per app
  defp run_app_bin(state, executable_path, command)

  defp run_app_bin(%{node: node, language: "elixir", port: port}, executable_path, command) do
    %Foundation.Catalog.Node{suffix: suffix} = Catalog.node_info(node)
    path = Common.remove_deployex_from_path()
    app_env = compose_app_env(Catalog.monitored_app_env())

    """
    unset $(env | grep '^RELEASE_' | awk -F'=' '{print $1}')
    unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
    #{app_env}
    export PATH=#{path}
    export RELEASE_NODE_SUFFIX=-#{suffix}
    export PORT=#{port}
    #{executable_path} #{command}
    """
  end

  defp run_app_bin(%{node: node, language: "erlang", port: port}, executable_path, "start") do
    %{sname: sname} = Catalog.node_info(node)
    path = Common.remove_deployex_from_path()
    cookie = Common.cookie()
    app_env = compose_app_env(Catalog.monitored_app_env())

    ssl_options =
      if Common.check_mtls() == :supported do
        "-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf"
      else
        ""
      end

    """
    unset $(env | grep '^RELEASE_' | awk -F'=' '{print $1}')
    unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
    #{app_env}
    export PATH=#{path}
    export RELX_REPLACE_OS_VARS=true
    export RELEASE_NODE=#{sname}
    export RELEASE_COOKIE=#{cookie}
    export RELEASE_SSL_OPTIONS=\"#{ssl_options}\"
    export PORT=#{port}
    #{executable_path} foreground
    """
  end

  defp run_app_bin(%{node: node, language: "gleam", port: port}, executable_path, "start") do
    %Foundation.Catalog.Node{sname: sname, name_string: app_name} = Catalog.node_info(node)
    path = Common.remove_deployex_from_path()
    cookie = Common.cookie()
    app_env = compose_app_env(Catalog.monitored_app_env())

    ssl_options =
      if Common.check_mtls() == :supported do
        "-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf"
      else
        ""
      end

    """
    unset $(env | grep '^RELEASE_' | awk -F'=' '{print $1}')
    unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
    #{app_env}
    export PATH=#{path}
    export PORT=#{port}
    PACKAGE=#{app_name}
    BASE=#{executable_path}
    erl \
      -pa "$BASE"/*/ebin \
      -eval "$PACKAGE@@main:run($PACKAGE)" \
      -noshell \
      #{ssl_options} \
      -sname #{sname} \
      -setcookie #{cookie}
    """
  end

  defp run_app_bin(%{node: node, language: language}, _executable_path, command) do
    msg =
      "Running not supported for language: #{language}, node: #{node}, command: #{command}"

    Logger.warning(msg)
    "echo \"#{msg}\""
  end

  defp compose_app_env([]), do: ""

  defp compose_app_env(env_list) do
    Enum.reduce(env_list, "export ", fn env, acc ->
      acc <> "#{env} "
    end)
  end

  # credo:disable-for-lines:28
  defp execute_pre_commands(_state, pre_commands, _bin_service) when pre_commands == [], do: :ok

  defp execute_pre_commands(
         %{node: node, status: status, language: language} = state,
         pre_commands,
         bin_service
       ) do
    migration_exec = Catalog.bin_path(node, language, bin_service)

    update_non_blocking_state(%{state | status: :pre_commands})

    Logger.info(" # Migration executable: #{migration_exec}")

    Enum.reduce_while(pre_commands, :ok, fn pre_command, acc ->
      Logger.info(" # Executing: #{pre_command}")

      Commander.run(run_app_bin(state, migration_exec, pre_command), [
        :sync,
        {:stdout, Catalog.stdout_path(node) |> to_charlist, [:append, {:mode, 0o600}]},
        {:stderr, Catalog.stderr_path(node) |> to_charlist, [:append, {:mode, 0o600}]}
      ])
      |> case do
        {:ok, _} ->
          {:cont, acc}

        {:error, reason} ->
          Logger.error(
            "Error running pre-command: #{pre_command} for node: #{node} reason: #{inspect(reason)}"
          )

          {:halt, {:error, :pre_commands}}
      end
    end)
    |> tap(fn _response -> update_non_blocking_state(%{state | status: status}) end)
  end

  defp cleanup_beam_process(node) do
    %{sname: sname} = Catalog.node_info(node)

    case Commander.run(
           "kill -9 $(ps -ax | grep \"#{Catalog.monitored_app_name()}/#{sname}/current/erts-*.*/bin/beam.smp\" | grep -v grep | awk '{print $1}') ",
           [:sync, :stdout, :stderr]
         ) do
      {:ok, _} ->
        Logger.warning("Remaining beam app removed for node: #{node}")

      {:error, _reason} ->
        # Logger.warning("Nothing to remove for node: #{node} - #{inspect(reason)}")
        :ok
    end
  end

  defp now, do: System.monotonic_time()

  defp table_name(node), do: (@monitor_table <> "-#{node}") |> String.to_atom()

  defp update_non_blocking_state(%{node: node} = state) do
    table_name(node)
    |> :ets.insert({:state, state})

    state
  end
end
