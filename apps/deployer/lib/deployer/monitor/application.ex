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
  @max_backoff_ms :timer.minutes(5)

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

  def handle_call(:restart, _from, state) when is_nil(state.current_pid) do
    {:reply, {:error, :application_is_not_running}, state}
  end

  # A worker of the previous version, during a relup, still calls and installs whatever the reply
  # says. The commands run here the old blocking way, and a failure stops the monitor and its app,
  # as the old MatchError did, so that hot upgrade fails instead of installing
  def handle_call({:run_pre_commands, pre_commands, app_bin_service}, _from, state) do
    case execute_pre_commands(state, pre_commands, app_bin_service) do
      :ok -> {:reply, {:ok, pre_commands}, state}
      {:error, _reason} = error -> {:stop, :pre_commands_failed, error, state}
    end
  end

  # A restart waits for a running pre-commands run, as it did behind the old blocking call, so
  # the current version's pre_commands never run next to the new version's
  def handle_call(:restart, _from, %Monitor{pre_commands_run: %{} = run} = state) do
    Logger.warning("Restart requested for sname: #{state.sname}, after the running pre-commands")

    {:reply, :ok, %{state | pre_commands_run: Map.put(run, :restart, true)}}
  end

  def handle_call(:restart, _from, state), do: {:reply, :ok, do_restart(state)}

  # Hot upgrade pre_commands run as erlexec processes that report their exit with a DOWN message.
  # A hot upgrade needs a running app, so the worker asks again while it is down or starting
  @impl true
  def handle_cast(
        {:start_pre_commands, _pre_commands, _app_bin_service, from, ref},
        %Monitor{} = state
      )
      when state.current_pid == nil or state.status != :running do
    send(from, {:pre_commands_result, ref, {:error, :busy}})
    {:noreply, state}
  end

  # The is_map_key check covers a state that a relup could not update
  def handle_cast(
        {:start_pre_commands, pre_commands, app_bin_service, from, ref},
        %Monitor{} = state
      )
      when not is_map_key(state, :pre_commands_run) or state.pre_commands_run == nil do
    Logger.info(" # Migration executable: #{Catalog.bin_path(state.sname, app_bin_service)}")

    run = %{
      from: from,
      # A run nobody waits for is stopped, so it cannot hold the monitor busy
      from_ref: Process.monitor(from),
      ref: ref,
      pre_commands: pre_commands,
      remaining: pre_commands,
      bin_service: app_bin_service,
      command: nil,
      exec_pid: nil,
      os_pid: nil
    }

    # The worker learns the run started, so a timeout can tell it from a request never taken
    send(from, {:pre_commands_started, ref})

    {:noreply, run_next_pre_command(state, run)}
  end

  def handle_cast({:start_pre_commands, _pre_commands, _app_bin_service, from, ref}, state) do
    send(from, {:pre_commands_result, ref, {:error, :busy}})
    {:noreply, state}
  end

  def handle_cast(
        {:cancel_pre_commands, ref},
        %Monitor{pre_commands_run: %{ref: ref} = run} = state
      ) do
    Logger.warning("Stopping pre-command: #{run.command} for sname: #{state.sname}")
    Commander.stop(run.os_pid)

    {:noreply, end_pre_commands_run(state, run)}
  end

  def handle_cast({:cancel_pre_commands, _ref}, state), do: {:noreply, state}

  @impl true
  # A crash restart waits for a running pre-commands run too, see the restart clause
  def handle_info({:run_service, sname}, %Monitor{pre_commands_run: %{} = run} = state)
      when sname == state.sname do
    {:noreply, %{state | pre_commands_run: Map.put(run, :run_service, true)}}
  end

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

    # NOTE: The application reached a stable state, so the backoff sequence starts
    #       over on the next crash. The crash_restart_count is a lifetime total and
    #       is never reset here.
    state = %{state | status: :running, consecutive_crash_count: 0}

    {:noreply, update_non_blocking_state(state)}
  end

  def handle_info({:check_running, _pid, _sname}, state) do
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, os_pid, :process, _pid, :normal},
        %Monitor{pre_commands_run: %{os_pid: os_pid} = run} = state
      ) do
    {:noreply, run_next_pre_command(state, run)}
  end

  def handle_info(
        {:DOWN, os_pid, :process, _pid, reason},
        %Monitor{pre_commands_run: %{os_pid: os_pid} = run} = state
      ) do
    Logger.error(
      "Error running pre-command: #{run.command} for sname: #{state.sname} reason: #{inspect(reason)}"
    )

    send(run.from, {:pre_commands_result, run.ref, {:error, :pre_commands}})

    {:noreply, end_pre_commands_run(state, run)}
  end

  def handle_info(
        {:DOWN, from_ref, :process, _pid, _reason},
        %Monitor{pre_commands_run: %{from_ref: from_ref} = run} = state
      ) do
    Logger.warning(
      "Stopping pre-command: #{run.command} for sname: #{state.sname}, nobody waits for it"
    )

    Commander.stop(run.os_pid)

    {:noreply, end_pre_commands_run(state, run)}
  end

  # A pre-command that was cancelled, or another erlexec process that ended
  def handle_info({:DOWN, _os_pid, :process, _pid, _reason}, state), do: {:noreply, state}

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

    # Crashes since the application was last seen running, it drives the backoff only
    consecutive_crash_count = state.consecutive_crash_count + 1

    Foundation.Notifications.notify("crash_restart", %{
      node: Node.self(),
      sname: state.sname,
      name: state.name,
      language: state.language,
      crash_restart_count: crash_restart_count
    })

    # Retry with backoff pattern, capped to avoid unbounded growth
    backoff = min(2 * consecutive_crash_count * 1000, @max_backoff_ms)
    trigger_run_service(state.sname, backoff)

    {:noreply,
     update_non_blocking_state(%{
       state
       | current_pid: nil,
         crash_restart_count: crash_restart_count,
         consecutive_crash_count: consecutive_crash_count
     })}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    Logger.warning(
      "Application sname: #{state.sname} with pid: #{inspect(pid)} being stopped by reason: #{inspect(reason)}"
    )

    {:noreply, state}
  end

  # erlexec does not stop a command it only monitors when its owner exits
  @impl true
  def terminate(_reason, %Monitor{pre_commands_run: %{os_pid: os_pid}}) when is_integer(os_pid),
    do: Commander.stop(os_pid)

  def terminate(_reason, _state), do: :ok

  # A state from a version without pre_commands_run gets the field on a relup
  @impl true
  def code_change(_old_vsn, state, _extra), do: {:ok, Map.put_new(state, :pre_commands_run, nil)}

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

  # The blocking call of the previous version, kept for its engine worker during a relup
  @impl true
  def run_pre_commands(sname, pre_commands, app_bin_service) do
    sname
    |> String.to_existing_atom()
    |> Common.call_gen_server({:run_pre_commands, pre_commands, app_bin_service})
  end

  @impl true
  def start_pre_commands(sname, pre_commands, app_bin_service) do
    case sname |> String.to_existing_atom() |> Process.whereis() do
      nil ->
        {:error, :not_running}

      pid ->
        # The monitor ref doubles as the request ref, so an exit mid-run reaches the caller
        ref = Process.monitor(pid)
        GenServer.cast(pid, {:start_pre_commands, pre_commands, app_bin_service, self(), ref})
        {:ok, ref}
    end
  end

  @impl true
  def cancel_pre_commands(sname, ref) do
    sname
    |> String.to_existing_atom()
    |> GenServer.cast({:cancel_pre_commands, ref})
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
      Foundation.Notifications.notify("deployment_started", %{
        node: Node.self(),
        sname: sname,
        version: version
      })

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
  #       - Unset DeployEx's own DEPLOYEX_* variables, which hold its secrets with the env adapter
  #       - Export RELEASE_NODE with sname
  #       - Export listening port that needs to be one per app
  defp run_app_bin(state, executable_path, command)

  defp run_app_bin(
         %{sname: sname, language: "elixir", ports: ports, env: env},
         executable_path,
         command
       ) do
    path = Common.remove_deployex_from_path()
    cookie = Common.cookie()
    app_env = build_export_command(env)

    ports_env =
      ports
      |> ports_to_env()
      |> build_export_command()

    # Set the distribution cookie, as the erlang and gleam clauses do. Without it the app
    # boots with its release default and DeployEx cannot connect over distribution when it
    # runs with a non-default cookie. It goes before app_env, so a RELEASE_COOKIE in the
    # app's env still wins.
    """
    unset $(env | grep -E '^(RELEASE|DEPLOYEX)_' | awk -F'=' '{print $1}')
    unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
    export RELEASE_COOKIE=#{Common.shell_quote(cookie)}
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
      if Common.mtls_certificate() do
        "-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf"
      else
        ""
      end

    """
    unset $(env | grep -E '^(RELEASE|DEPLOYEX)_' | awk -F'=' '{print $1}')
    unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
    #{app_env}
    #{ports_env}
    export PATH=#{path}
    export RELX_REPLACE_OS_VARS=true
    export RELEASE_NODE=#{sname}
    export RELEASE_COOKIE=#{Common.shell_quote(cookie)}
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
      if Common.mtls_certificate() do
        "-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf"
      else
        ""
      end

    """
    unset $(env | grep -E '^(RELEASE|DEPLOYEX)_' | awk -F'=' '{print $1}')
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
      -setcookie #{Common.shell_quote(cookie)}
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

  # Quote each value, so spaces and shell characters reach the monitored app as written
  defp build_export_command(env_list) do
    Enum.reduce(env_list, "export ", fn env, acc ->
      acc <> "#{quote_env_value(env)} "
    end)
  end

  defp quote_env_value(env) do
    case String.split(env, "=", parts: 2) do
      [key, value] -> "#{key}=#{Common.shell_quote(value)}"
      [key] -> key
    end
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

  # A hot upgrade needs the app up. When it went down, or a restart waits on the run, the reply
  # says the pre_commands ran, so the worker waits for the app without running them again
  defp run_next_pre_command(state, %{remaining: []} = run) do
    app_down? = state.current_pid == nil or state.status != :running

    result =
      if run[:restart] || run[:run_service] || app_down?,
        do: {:error, :app_down},
        else: {:ok, run.pre_commands}

    send(run.from, {:pre_commands_result, run.ref, result})

    end_pre_commands_run(state, run)
  end

  defp run_next_pre_command(%Monitor{sname: sname} = state, %{remaining: [command | rest]} = run) do
    Logger.info(" # Executing: #{command}")

    state
    |> run_app_bin(Catalog.bin_path(sname, run.bin_service), command)
    |> Commander.run([
      :monitor,
      # Its own process group, so a stop also ends the BEAM that `bin/app eval` starts
      {:group, 0},
      :kill_group,
      {:stdout, Catalog.stdout_path(sname) |> to_charlist, [:append, {:mode, 0o600}]},
      {:stderr, Catalog.stderr_path(sname) |> to_charlist, [:append, {:mode, 0o600}]}
    ])
    |> case do
      {:ok, exec_pid, os_pid} ->
        run = %{run | remaining: rest, command: command, exec_pid: exec_pid, os_pid: os_pid}
        state = Map.put(state, :pre_commands_run, run)

        # The dashboard shows the migration, the application itself keeps its status
        update_non_blocking_state(%{state | status: :pre_commands})
        state

      {:error, reason} ->
        Logger.error(
          "Error running pre-command: #{command} for sname: #{sname} reason: #{inspect(reason)}"
        )

        send(run.from, {:pre_commands_result, run.ref, {:error, :pre_commands}})
        end_pre_commands_run(state, run)
    end
  end

  defp end_pre_commands_run(state, %{from_ref: from_ref} = run) do
    Process.demonitor(from_ref, [:flush])
    state = update_non_blocking_state(Map.put(state, :pre_commands_run, nil))

    # do_restart schedules run_service itself. A restart for an application that is already
    # down is dropped, its crash restart has its own run_service
    cond do
      run[:restart] && state.current_pid != nil ->
        do_restart(state)

      run[:run_service] ->
        trigger_run_service(state.sname)
        state

      true ->
        state
    end
  end

  defp do_restart(state) do
    Logger.warning("Restart requested for sname: #{state.sname}")

    Foundation.Notifications.notify("deployment_shutdown", %{
      node: node(),
      sname: "#{state.sname}"
    })

    # Stop current application
    Commander.stop(state.current_pid)

    cleanup_beam_process(state.sname)

    # Update the number of force restarts
    force_restart_count = state.force_restart_count + 1

    # Trigger restart with backoff time of 1 second
    trigger_run_service(state.sname, 1_000)

    # The app is down until run_service starts it again. Without a current pid, its exit is not
    # taken for a crash, which would start it a second time
    update_non_blocking_state(%{
      state
      | current_pid: nil,
        force_restart_count: force_restart_count,
        status: :starting
    })
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
