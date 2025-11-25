defmodule Deployer.Monitor.Application do
  @moduledoc """
  GenServer that monitor and supervise the application.
  """
  use GenServer
  require Logger

  alias Deployer.Engine
  alias Deployer.Monitor
  alias Deployer.Status
  alias Foundation.Catalog
  alias Foundation.Common
  alias Host.Commander

  @behaviour Monitor.Adapter

  @monitor_table "monitor-table"
  @new_deploy_topic "deployex::new_deploy"

  ### ==========================================================================
  ### Callback functions
  ### ==========================================================================

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(%Monitor.Service{sname: sname} = service) do
    GenServer.start_link(__MODULE__, service, name: String.to_atom(sname))
  end

  @impl true
  def init(%Monitor.Service{sname: sname, language: language} = service) do
    Process.flag(:trap_exit, true)

    # NOTE: This ETS table provides non-blocking access to the state.
    :ets.new(table_name(sname), [:set, :protected, :named_table])

    Logger.info("Initializing monitor server for sname: #{sname} language: #{language}")

    trigger_run_service(sname)

    {:ok,
     update_non_blocking_state(%Monitor{
       timeout_app_ready: service.timeout_app_ready,
       retry_delay_pre_commands: service.retry_delay_pre_commands,
       name: service.name,
       sname: service.sname,
       ports: service.ports,
       language: language,
       env: service.env
     })}
  end

  @impl true
  def handle_call(
        :stop_service,
        _from,
        %Monitor{current_pid: current_pid, sname: sname} = state
      )
      when is_nil(current_pid) do
    Logger.warning("Requested sname: #{sname} to stop but application is not running.")

    {:reply, :ok, state}
  end

  def handle_call(
        :stop_service,
        _from,
        %Monitor{sname: sname, current_pid: pid} = state
      ) do
    Logger.info("Requested sname: #{sname} to stop application pid: #{inspect(pid)}")

    # Stop current application
    Commander.stop(state.current_pid)

    # NOTE: The next command is needed for Systems that have a different PID for the "/bin/app start" script
    #       and the bin/beam.smp process
    cleanup_beam_process(state.sname)

    {:reply, :ok, state}
  end

  # This command is available during the hot HotUpgrade. If it fails, the process will
  # restart and attempt a full deployment.
  def handle_call({:run_pre_commands, pre_commands, app_bin_service}, _from, state) do
    :ok = execute_pre_commands(state, pre_commands, app_bin_service)

    {:reply, {:ok, pre_commands}, state}
  end

  def handle_call(:restart, _from, state) when is_nil(state.current_pid) do
    {:reply, {:error, :application_is_not_running}, state}
  end

  def handle_call(:restart, _from, state) do
    Logger.warning("Restart requested for sname: #{state.sname}")

    # Stop current application
    Commander.stop(state.current_pid)

    cleanup_beam_process(state.sname)

    # Update the number of force restarts
    force_restart_count = state.force_restart_count + 1

    # Trigger restart with backoff time of 1 second
    trigger_run_service(state.sname, 1_000)

    {:reply, :ok, update_non_blocking_state(%{state | force_restart_count: force_restart_count})}
  end

  @impl true
  def handle_info({:run_service, sname}, %Monitor{} = state)
      when sname == state.sname do
    version_map = Status.current_version_map(state.sname)
    version = version_map.version

    state =
      if version == nil do
        Logger.info("No version set, not able to run_service")
        state
      else
        Logger.info("Ensure running requested for sname: #{sname} version: #{version}")

        run_service(state, version_map)
      end

    {:noreply, update_non_blocking_state(state)}
  end

  def handle_info({:check_running, pid, sname}, state)
      when pid == state.current_pid and sname == state.sname do
    Logger.info(" # Application sname: #{state.sname} is running")

    Engine.notify_application_running(sname)

    {:noreply, update_non_blocking_state(%{state | status: :running})}
  end

  def handle_info({:check_running, _pid, _sname}, state) do
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
      "Unexpected exit message received for sname: #{state.sname} from pid: #{inspect(pid)}, application being restarted"
    )

    cleanup_beam_process(state.sname)

    # Update the number of crash restarts
    crash_restart_count = state.crash_restart_count + 1

    # Retry with backoff pattern
    trigger_run_service(state.sname, 2 * crash_restart_count * 1000)

    {:noreply,
     update_non_blocking_state(%{
       state
       | current_pid: nil,
         crash_restart_count: crash_restart_count
     })}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    Logger.warning(
      "Application sname: #{state.sname} with pid: #{inspect(pid)} being stopped by reason: #{inspect(reason)}"
    )

    {:noreply, state}
  end

  ### ==========================================================================
  ### Public functions
  ### ==========================================================================
  @impl true
  def state(sname) do
    [{_, value}] =
      table_name(sname)
      |> :ets.lookup(:state)

    value
  rescue
    _ ->
      %Monitor{}
  end

  @impl true
  def run_pre_commands(sname, pre_commands, app_bin_service) do
    sname
    |> String.to_existing_atom()
    |> Common.call_gen_server({:run_pre_commands, pre_commands, app_bin_service})
  end

  @impl true
  defdelegate start_service(service), to: Monitor.Supervisor

  @impl true
  defdelegate stop_service(name, sname), to: Monitor.Supervisor

  @impl true
  defdelegate list, to: Monitor.Supervisor

  @impl true
  defdelegate list(options), to: Monitor.Supervisor

  @impl true
  def subscribe_new_deploy do
    Phoenix.PubSub.subscribe(Deployer.PubSub, @new_deploy_topic)
  end

  @impl true
  def restart(sname) do
    sname
    |> String.to_existing_atom()
    |> Common.call_gen_server(:restart)
  end

  def global_name(sname),
    do: %{module: __MODULE__, sname: sname}

  ### ==========================================================================
  ### Private functions
  ### ==========================================================================
  defp trigger_run_service(sname, timeout \\ 1),
    do: Process.send_after(self(), {:run_service, sname}, timeout)

  defp run_service(
         %Monitor{
           sname: sname,
           timeout_app_ready: timeout_app_ready,
           retry_delay_pre_commands: retry_delay_pre_commands
         } = state,
         version_map
       ) do
    app_exec = Catalog.bin_path(sname, :current)
    version = version_map.version

    notify_new_deploy = fn ->
      Phoenix.PubSub.broadcast(
        Deployer.PubSub,
        @new_deploy_topic,
        {:new_deploy, Node.self(), sname}
      )
    end

    with true <- File.exists?(app_exec),
         :ok <- notify_new_deploy.(),
         :ok <- Logger.info(" # Identified executable: #{app_exec}"),
         :ok <- execute_pre_commands(state, version_map.pre_commands, :current) do
      Logger.info(" # Starting application")

      {:ok, pid, os_pid} =
        Commander.run_link(
          run_app_bin(state, app_exec, "start"),
          [
            {:stdout, Catalog.stdout_path(sname) |> to_charlist, [:append, {:mode, 0o600}]},
            {:stderr, Catalog.stderr_path(sname) |> to_charlist, [:append, {:mode, 0o600}]}
          ]
        )

      Logger.info(
        " # Running sname: #{sname}, monitoring pid = #{inspect(pid)}, OS process = #{os_pid} sname: #{sname}"
      )

      Process.send_after(self(), {:check_running, pid, sname}, timeout_app_ready)

      %{state | current_pid: pid, status: :starting, start_time: now()}
    else
      false ->
        trigger_run_service(sname, retry_delay_pre_commands)
        Logger.error("Version: #{version} set but no #{app_exec}")
        state

      {:error, :pre_commands} ->
        trigger_run_service(sname, retry_delay_pre_commands)
        %{state | status: :pre_commands}
    end
  end

  # NOTE: Some commands need to run prior starting the application
  #       - Unset env vars from the deployex release to not mix with the monitored app release
  #       - Export RELEASE_NODE with sname
  #       - Export listening port that needs to be one per app
  defp run_app_bin(state, executable_path, command)

  defp run_app_bin(
         %{sname: sname, language: "elixir", ports: ports, env: env},
         executable_path,
         command
       ) do
    path = Common.remove_deployex_from_path()
    app_env = build_export_command(env)

    ports_env =
      ports
      |> ports_to_env()
      |> build_export_command()

    """
    unset $(env | grep '^RELEASE_' | awk -F'=' '{print $1}')
    unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
    #{app_env}
    #{ports_env}
    export PATH=#{path}
    export RELEASE_NODE=#{sname}
    #{executable_path} #{command}
    """
  end

  defp run_app_bin(
         %{sname: sname, language: "erlang", ports: ports, env: env},
         executable_path,
         "start"
       ) do
    path = Common.remove_deployex_from_path()
    cookie = Common.cookie()
    app_env = build_export_command(env)

    ports_env =
      ports
      |> ports_to_env()
      |> build_export_command()

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
    #{ports_env}
    export PATH=#{path}
    export RELX_REPLACE_OS_VARS=true
    export RELEASE_NODE=#{sname}
    export RELEASE_COOKIE=#{cookie}
    export RELEASE_SSL_OPTIONS=\"#{ssl_options}\"
    #{executable_path} foreground
    """
  end

  defp run_app_bin(
         %{sname: sname, language: "gleam", ports: ports, env: env},
         executable_path,
         "start"
       ) do
    %{name: name} = Catalog.node_info(sname)
    path = Common.remove_deployex_from_path()
    cookie = Common.cookie()
    app_env = build_export_command(env)

    ports_env =
      ports
      |> ports_to_env()
      |> build_export_command()

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
    #{ports_env}
    export PATH=#{path}
    PACKAGE=#{name}
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

  defp run_app_bin(%{sname: sname, language: language}, _executable_path, command) do
    msg =
      "Running not supported for language: #{language}, sname: #{sname}, command: #{command}"

    Logger.warning(msg)
    "echo \"#{msg}\""
  end

  defp ports_to_env(ports), do: Enum.map(ports, fn port -> "#{port.key}=#{port.base}" end)

  defp build_export_command([]), do: ""

  defp build_export_command(env_list) do
    Enum.reduce(env_list, "export ", fn env, acc ->
      acc <> "#{env} "
    end)
  end

  defp execute_pre_commands(_state, pre_commands, _bin_service) when pre_commands == [], do: :ok

  defp execute_pre_commands(
         %{sname: sname, status: status} = state,
         pre_commands,
         bin_service
       ) do
    migration_exec = Catalog.bin_path(sname, bin_service)

    update_non_blocking_state(%{state | status: :pre_commands})

    Logger.info(" # Migration executable: #{migration_exec}")

    Enum.reduce_while(pre_commands, :ok, fn pre_command, acc ->
      Logger.info(" # Executing: #{pre_command}")

      Commander.run(run_app_bin(state, migration_exec, pre_command), [
        :sync,
        {:stdout, Catalog.stdout_path(sname) |> to_charlist, [:append, {:mode, 0o600}]},
        {:stderr, Catalog.stderr_path(sname) |> to_charlist, [:append, {:mode, 0o600}]}
      ])
      |> case do
        {:ok, _} ->
          {:cont, acc}

        {:error, reason} ->
          Logger.error(
            "Error running pre-command: #{pre_command} for sname: #{sname} reason: #{inspect(reason)}"
          )

          {:halt, {:error, :pre_commands}}
      end
    end)
    |> tap(fn _response -> update_non_blocking_state(%{state | status: status}) end)
  end

  defp cleanup_beam_process(sname) do
    %{sname: sname, name: name} = Catalog.node_info(sname)

    case Commander.run(
           "kill -9 $(ps -ax | grep \"#{name}/#{sname}/current/erts-*.*/bin/beam.smp\" | grep -v grep | awk '{print $1}') ",
           [:sync, :stdout, :stderr]
         ) do
      {:ok, _} ->
        Logger.warning("Remaining beam app removed for sname: #{sname}")

      {:error, _reason} ->
        # Logger.warning("Nothing to remove for sname: #{sname} - #{inspect(reason)}")
        :ok
    end
  end

  defp now, do: System.monotonic_time()

  defp table_name(sname), do: (@monitor_table <> "-#{sname}") |> String.to_atom()

  defp update_non_blocking_state(%{sname: sname} = state) do
    table_name(sname)
    |> :ets.insert({:state, state})

    state
  end
end
